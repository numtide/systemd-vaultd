package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path"
	"strings"
	"syscall"
	"time"
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
	var content []byte
	for i := 0; i < 10; i++ {
		jsonStat, err := os.Stat(jsonPath)
		if err != nil {
			if os.IsNotExist(err) {
				// wait for the file to be created
				fmt.Printf("waiting for %s to be created", jsonPath)
				time.Sleep(1 * time.Second)
				continue
			}
			return fmt.Errorf("failed to stat vault json file %s: %w", serviceName, err)
		}

		if jsonStat.ModTime().Before(stat.ModTime()) {
			// wait for the file to be updated
			fmt.Printf("waiting for %s to be updated", jsonPath)
			time.Sleep(1 * time.Second)
			continue
		}

		content, err = os.ReadFile(jsonPath)
		if err != nil {
			if os.IsNotExist(err) {
				// wait for the file to be created
				fmt.Printf("waiting for %s to be created", jsonPath)
				time.Sleep(1 * time.Second)
				continue
			}
			return fmt.Errorf("failed to read vault json file %s: %w", serviceName, err)
		}
		break
	}
	var data map[string]interface{}
	if err := json.Unmarshal(content, &data); err != nil {
		return fmt.Errorf("failed to unmarshal json from %s: %w", jsonPath, err)
	}
	for key, value := range data {
		targetPath := path.Join(target, key)
		tempPath := targetPath + ".tmp"
		err = os.WriteFile(tempPath, []byte(value.(string)), 0o400)
		if err != nil {
			return fmt.Errorf("failed to write file %s: %w", targetPath, err)
		}
		err = os.Chown(tempPath, int(uid), int(gid))
		if err != nil {
			return fmt.Errorf("failed to chown file %s: %w", targetPath, err)
		}
		err = os.Rename(tempPath, targetPath)
		if err != nil {
			return fmt.Errorf("failed to rename file %s: %w", targetPath, err)
		}
	}
	err = os.Chtimes(target, time.Now(), time.Now())
	if err != nil {
		log.Printf("failed to update modification time of %s: %v", target, err)
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
