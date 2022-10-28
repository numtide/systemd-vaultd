package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

type server struct {
	Socket           string
	SecretDir        string
	epfd             int
	inotifyRequests  chan inotifyRequest
	connectionClosed chan int
}

func inheritSocket() *net.UnixListener {
	socks := systemdSockets(true)
	stat := &syscall.Stat_t{}
	for _, s := range socks {
		fd := s.Fd()
		err := syscall.Fstat(int(fd), stat)
		if err != nil {
			log.Printf("Received invalid file descriptor from systemd for fd%d: %v", fd, err)
			continue
		}
		listener, err := net.FileListener(s)
		if err != nil {
			log.Printf("Received file descriptor %d from systemd that is not a valid socket: %v", fd, err)
			continue
		}
		unixListener, ok := listener.(*net.UnixListener)
		if !ok {
			log.Printf("Ignore file descriptor %d from systemd, which is not a unix socket", fd)
			continue
		}
		log.Printf("Use unix socket received from systemd")
		return unixListener
	}
	return nil
}

func listenSocket(path string) (*net.UnixListener, error) {
	s := inheritSocket()
	if s != nil {
		return s, nil
	}
	if err := syscall.Unlink(path); err != nil && !os.IsNotExist(err) {
		return nil, fmt.Errorf("Cannot remove old socket: %v", err)
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		return nil, fmt.Errorf("'%s' is not a valid socket path: %v", path, err)
	}
	addr, err := net.ResolveUnixAddr("unix", abs)
	if err != nil {
		return nil, fmt.Errorf("Failed to resolv '%s' as a unix address: %v", abs, err)
	}
	listener, err := net.ListenUnix("unix", addr)
	if err != nil {
		return nil, fmt.Errorf("Failed to open socket at %s: %v", addr.Name, err)
	}
	return listener, nil
}

func parseCredentialsAddr(addr string) (*string, *string, error) {
	// Systemd stores metadata in its local unix address
	fields := strings.Split(addr, "/")
	if len(fields) != 4 || fields[1] != "unit" {
		return nil, nil, fmt.Errorf("Address needs to match this format: @<random_hex>/unit/<service_name>/<secret_id>, got '%s'", addr)
	}
	return &fields[2], &fields[3], nil
}

func (s *server) queueInotifyRequest(conn *net.UnixConn, filename string, key string) error {
	log.Printf("Block start until %s appears", filename)
	fd, err := connFd(conn)
	if err != nil {
		// connection was closed while we trying to wait
		return err
	}
	if err := s.epollWatch(fd); err != nil {
		log.Printf("Cannot get setup epoll for unix socket: %s", err)
		return err
	}
	s.inotifyRequests <- inotifyRequest{filename: filename, key: key, conn: conn}
	return nil
}

func (s *server) serveServiceEnvironment(conn *net.UnixConn, unit string, secret string) {
	shouldClose := true
	defer func() {
		if shouldClose {
			conn.Close()
		}
	}()

	log.Printf("Systemd requested environment file for %s from %s", secret, unit)
	secretPath := filepath.Join(s.SecretDir, secret)

	f, err := os.Open(secretPath)
	if errors.Is(err, os.ErrNotExist) {
		if s.queueInotifyRequest(conn, secret, secret) == nil {
			shouldClose = false
		}
		return
	} else if err != nil {
		log.Printf("Cannot open environment file %s/%s: %v", unit, secret, err)
		return
	}
	defer f.Close()
	if _, err = io.Copy(conn, f); err != nil {
		log.Printf("Failed to send environment file: %v", err)
	}
}

func (s *server) serveServiceSecrets(conn *net.UnixConn, unit string, secret string) {
	shouldClose := true
	defer func() {
		if shouldClose {
			conn.Close()
		}
	}()

	log.Printf("Systemd requested secret for %s/%s", unit, secret)
	secretName := unit + ".json"
	secretPath := filepath.Join(s.SecretDir, secretName)
	secretMap, err := parseServiceSecrets(secretPath)
	if errors.Is(err, os.ErrNotExist) {
		if s.queueInotifyRequest(conn, secretName, secret) == nil {
			shouldClose = false
		}
		return
	} else if err != nil {
		log.Printf("Cannot process secret %s/%s: %v", unit, secret, err)
		return
	}
	val, ok := secretMap[secret]
	if ok {
		if _, err = io.WriteString(conn, fmt.Sprint(val)); err != nil {
			log.Printf("Failed to send secret: %v", err)
		}
	} else {
		log.Printf("Secret map at %s has no value for key %s", secretPath, secret)
	}
}

func (s *server) serveConnection(conn *net.UnixConn) {
	addr := conn.RemoteAddr().String()
	unit, secret, err := parseCredentialsAddr(addr)
	if err != nil {
		conn.Close()
		log.Printf("Received connection but remote unix address seems to be not from systemd: %v", err)
		return
	}

	if isEnvironmentFile(*secret) {
		s.serveServiceEnvironment(conn, *unit, *secret)
	} else {
		s.serveServiceSecrets(conn, *unit, *secret)
	}
}

func serveSecrets(s *server) error {
	l, err := listenSocket(s.Socket)
	if err != nil {
		return fmt.Errorf("Failed to setup listening socket: %v", err)
	}
	defer l.Close()
	log.Printf("Listening on %s", s.Socket)
	go s.handleEpoll()
	for {
		conn, err := l.AcceptUnix()
		if err != nil {
			return fmt.Errorf("Error accepting unix connection: %v", err)
		}
		go s.serveConnection(conn)
	}
}

var secretDir, socketDir string

func init() {
	defaultDir := os.Getenv("SYSTEMD_VAULT_SECRETS")
	if defaultDir == "" {
		defaultDir = "/run/systemd-vaultd/secrets"
	}
	flag.StringVar(&secretDir, "secrets", defaultDir, "directory where secrets are looked up")

	defaultSock := os.Getenv("SYSTEMD_VAULT_SOCK")
	if defaultSock == "" {
		defaultSock = "/run/systemd-vaultd/sock"
	}
	flag.StringVar(&socketDir, "sock", defaultSock, "unix socket to listen to for systemd requests")
	flag.Parse()
}

func createServer(secretDir string, socketDir string) (*server, error) {
	epfd, err := syscall.EpollCreate1(syscall.EPOLL_CLOEXEC)
	if epfd == -1 {
		return nil, fmt.Errorf("failed to create epoll fd: %v", err)
	}
	s := &server{
		Socket:           socketDir,
		SecretDir:        secretDir,
		epfd:             epfd,
		inotifyRequests:  make(chan inotifyRequest),
		connectionClosed: make(chan int),
	}
	if err := s.setupWatcher(secretDir); err != nil {
		return nil, fmt.Errorf("Failed to setup file system watcher: %v", err)
	}
	return s, nil
}

func main() {
	s, err := createServer(secretDir, socketDir)
	if err != nil {
		log.Fatalf("Failed to create server: %v", err)
	}
	if err := serveSecrets(s); err != nil {
		log.Fatalf("Failed serve secrets: %v", err)
	}
}
