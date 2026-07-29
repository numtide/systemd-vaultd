package main

import (
	"fmt"
	"log"
	"os"
	"path"
	"strings"
	"syscall"
	"time"

	"github.com/numtide/systemd-vaultd/internal"
)

const (
	systemdVaultdir = "/run/systemd-vaultd/secrets"
)

func updateSecrets(serviceName, target string) error {
	// get systemd service name from credentials directory
	stat, err := os.Stat(target)
	if err != nil {
		return fmt.Errorf("failed to stat target %s: %w", target, err)
	}
	// inherit the owner and group of the credentials directory
	uid := stat.Sys().(*syscall.Stat_t).Uid
	gid := stat.Sys().(*syscall.Stat_t).Gid

	jsonPath := path.Join(systemdVaultdir, fmt.Sprintf("%s.json", serviceName))
	for i := 0; i < 10; i++ {
		jsonStat, err := os.Stat(jsonPath)
		if err != nil {
			if os.IsNotExist(err) {
				// wait for the file to be created
				log.Printf("waiting for %s to be created", jsonPath)
				time.Sleep(1 * time.Second)
				continue
			}
			return fmt.Errorf("failed to stat vault json file %s: %w", serviceName, err)
		}

		if jsonStat.ModTime().Before(stat.ModTime()) && i < 9 {
			// wait for the file to be updated
			log.Printf("waiting for %s to be updated", jsonPath)
			time.Sleep(1 * time.Second)
			continue
		}

		break
	}
	data, err := internal.ParseServiceSecrets(jsonPath)
	if err != nil {
		return err
	}
	for key, value := range data {
		if err := writeSecret(target, key, internal.SecretBytes(value), uid, gid); err != nil {
			return err
		}
	}
	err = os.Chtimes(target, time.Now(), time.Now())
	if err != nil {
		log.Printf("failed to update modification time of %s: %v", target, err)
	}

	return nil
}

// writeSecret atomically replaces target/key. This runs as root inside a
// directory owned by the service user, so it must not follow symlinks:
// the temp file is created with O_EXCL and chowned via its fd.
func writeSecret(target, key string, content []byte, uid, gid uint32) error {
	targetPath := path.Join(target, key)
	f, err := os.CreateTemp(target, "."+key+".tmp*")
	if err != nil {
		return fmt.Errorf("failed to create temporary file for %s: %w", targetPath, err)
	}
	tempPath := f.Name()
	defer func() {
		f.Close()
		os.Remove(tempPath)
	}()
	if _, err := f.Write(content); err != nil {
		return fmt.Errorf("failed to write file %s: %w", targetPath, err)
	}
	if err := f.Chown(int(uid), int(gid)); err != nil {
		return fmt.Errorf("failed to chown file %s: %w", targetPath, err)
	}
	if err := f.Chmod(0o400); err != nil {
		return fmt.Errorf("failed to chmod file %s: %w", targetPath, err)
	}
	if err := f.Close(); err != nil {
		return fmt.Errorf("failed to close file %s: %w", targetPath, err)
	}
	if err := os.Rename(tempPath, targetPath); err != nil {
		return fmt.Errorf("failed to rename file %s: %w", targetPath, err)
	}
	return nil
}

func getSystemdServiceName() (string, error) {
	mainPid := os.Getenv("MAINPID")
	if mainPid == "" {
		return "", fmt.Errorf("MAINPID not set")
	}
	p := fmt.Sprintf("/proc/%s/cgroup", mainPid)
	content, err := os.ReadFile(p)
	if err != nil {
		return "", fmt.Errorf("failed to read cgroup file %s: %w", p, err)
	}
	line := strings.SplitN(string(content), "\n", 2)[0]
	if !strings.HasSuffix(line, ".service") {
		return "", fmt.Errorf("cgroup file %s does not end with .service", p)
	}
	return path.Base(line), nil
}

func main() {
	if len(os.Args) != 2 {
		fmt.Println("Usage: systemd-vaultd-update-secrets <target>")
		os.Exit(1)
	}
	serviceName, err := getSystemdServiceName()
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	target := os.Args[1]
	if err := updateSecrets(serviceName, target); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
