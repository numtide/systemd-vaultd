package main

import (
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

type inotifyRequest struct {
	filename string
	conn     *net.UnixConn
}

type connection struct {
	fd         int
	connection *net.UnixConn
}

func readEvents(inotifyFd int, events chan string) {
	var buf [syscall.SizeofInotifyEvent * 4096]byte // Buffer for a maximum of 4096 raw events
	for {
		n, err := syscall.Read(inotifyFd, buf[:])
		// If a signal interrupted execution, see if we've been asked to close, and try again.
		// http://man7.org/linux/man-pages/man7/signal.7.html :
		// "Before Linux 3.8, reads from an inotify(7) file descriptor were not restartable"
		if errors.Is(err, syscall.EINTR) {
			continue
		}

		if n < syscall.SizeofInotifyEvent {
			if n == 0 {
				log.Fatalf("notify: read EOF from inotify (cause: %v)", err)
			} else if n < 0 {
				log.Fatalf("notify: Received error while reading from inotify: %v", err)
			} else {
				log.Fatal("notify: short read in readEvents()")
			}
			continue
		}
		var offset uint32
		for offset <= uint32(n-syscall.SizeofInotifyEvent) {
			// Point "raw" to the event in the buffer
			raw := (*syscall.InotifyEvent)(unsafe.Pointer(&buf[offset]))

			mask := uint32(raw.Mask)
			nameLen := uint32(raw.Len)

			if mask&syscall.IN_Q_OVERFLOW != 0 {
				// TODO Re-scan all files in this case
				log.Fatal("Overflow in inotify")
			}
			if nameLen > 0 {
				// Point "bytes" at the first byte of the filename
				bytes := (*[syscall.PathMax]byte)(unsafe.Pointer(&buf[offset+syscall.SizeofInotifyEvent]))
				// The filename is padded with NULL bytes. TrimRight() gets rid of those.
				fname := strings.TrimRight(string(bytes[0:nameLen]), "\000")
				log.Printf("Detected added file: %s", fname)
				events <- fname
			}

			// Move to the next event in the buffer
			offset += syscall.SizeofInotifyEvent + nameLen
		}
	}
}

func connFd(conn *net.UnixConn) (int, error) {
	file, err := conn.File()
	if err != nil {
		return -1, err
	}
	return int(file.Fd()), nil
}

func (s *server) watch(inotifyFd int) {
	connsForPath := make(map[string][]connection)
	fdToPath := make(map[int]string)

	defer syscall.Close(inotifyFd)

	fsEvents := make(chan string)
	go readEvents(inotifyFd, fsEvents)
	for {
		select {
		case req, ok := <-s.inotifyRequests:
			if !ok {
				return
			}
			fd, err := connFd(req.conn)
			if err != nil {
				log.Println("Received inotify request for closed connection")
				continue
			}
			fdToPath[fd] = req.filename
			conns, ok := connsForPath[req.filename]
			if ok {
				connsForPath[req.filename] = append(conns, connection{fd, req.conn})
				continue
			}

			connsForPath[req.filename] = []connection{{fd, req.conn}}
		case fname, ok := <-fsEvents:
			if !ok {
				return
			}
			conns := connsForPath[fname]
			if conns == nil {
				log.Printf("Ignore unknown file: %s", fname)
				continue
			}
			delete(connsForPath, fname)

			for _, conn := range conns {
				defer delete(fdToPath, conn.fd)

				f, err := os.Open(filepath.Join(s.SecretDir, fname))
				if err == nil {
					defer f.Close()

					_, err := io.Copy(conn.connection, f)
					if err == nil {
						log.Printf("Served %s to %s", fname, conn.connection.RemoteAddr().String())
					} else {
						log.Printf("Failed to send secret: %v", err)
					}
					if err := s.epollDelete(conn.fd); err != nil {
						log.Printf("failed to remove socket from epoll: %s", err)
					}
					if err := syscall.Shutdown(conn.fd, syscall.SHUT_RDWR); err != nil {
						log.Printf("Failed to shutdown socket: %v", err)
					}
				} else {
					log.Printf("Failed to open secret: %v", err)
				}
			}
		case fd, ok := <-s.connectionClosed:
			if !ok {
				return
			}
			path := fdToPath[fd]
			delete(fdToPath, fd)
			conns := connsForPath[path]
			if conns == nil {
				// watcher has been already deregistered
				return
			}
			for idx, c := range conns {
				if c.fd == fd {
					last := len(conns) - 1
					conns[idx] = conns[last]
					conns = conns[:last]

					c.connection.Close()
					break
				}
			}
			if len(conns) == 0 {
				delete(connsForPath, path)
			}
		}
	}
}

func (s *server) setupWatcher(dir string) error {
	fd, err := syscall.InotifyInit1(syscall.IN_CLOEXEC)
	if err != nil {
		return fmt.Errorf("Failed to initialize inotify: %v", err)
	}
	flags := uint32(syscall.IN_CREATE | syscall.IN_MOVED_TO | syscall.IN_ONLYDIR)
	res := os.MkdirAll(dir, 0700)
	if err != nil && !os.IsNotExist(res) {
		return fmt.Errorf("Failed to create secret directory: %v", err)
	}
	if _, err = syscall.InotifyAddWatch(fd, dir, flags); err != nil {
		return fmt.Errorf("Failed to initialize inotify on secret directory %s: %v", dir, err)
	}
	go s.watch(fd)
	return nil
}
