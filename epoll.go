package main

import (
	"log"
	"syscall"
)

const (
	EPOLLET = 1 << 31
)

func (s *server) epollWatch(fd int) error {
	event := syscall.EpollEvent{
		Fd:     int32(fd),
		Events: syscall.EPOLLHUP | EPOLLET,
	}
	return syscall.EpollCtl(s.epfd, syscall.EPOLL_CTL_ADD, fd, &event)
}

func (s *server) epollDelete(fd int) error {
	return syscall.EpollCtl(s.epfd, syscall.EPOLL_CTL_DEL, fd, &syscall.EpollEvent{})
}

func (s *server) handleEpoll() {
	events := make([]syscall.EpollEvent, 1024)
	for {
		n, errno := syscall.EpollWait(s.epfd, events, -1)
		if n == -1 {
			if errno == syscall.EINTR {
				continue
			}
			log.Fatalf("connection cleaner: epoll wait failed with %v", errno)
		}
		ready := events[:n]
		for _, event := range ready {
			if event.Events&(syscall.EPOLLHUP|syscall.EPOLLERR) != 0 {
				if err := s.epollDelete(int(event.Fd)); err != nil {
					log.Printf("failed to remove socket from epoll: %s", err)
				}
				s.connectionClosed <- int(event.Fd)
			} else {
				log.Printf("Unhandled epoll event: %d for fd %d", event.Events, event.Fd)
			}
		}
	}
}
