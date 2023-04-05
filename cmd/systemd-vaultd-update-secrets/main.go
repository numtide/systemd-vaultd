package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path"
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
		os.Chown(path.Dir(targetPath), int(uid), int(gid))

		if err != nil {
			return fmt.Errorf("failed to create directory %s: %w", path.Dir(targetPath), err)
		}
		os.WriteFile(targetPath, []byte(value.(string)), 0o400)
		os.Chown(targetPath, int(uid), int(gid))
	}

	return nil
}

func main() {
	if len(os.Args) != 2 {
		fmt.Println("Usage: systemd-vaultd-update-secrets <target>")
		os.Exit(1)
	}
	serviceName := os.Getenv("SYSTEMD_ACTIVATION_UNIT")
	if serviceName == "" {
		fmt.Println("SYSTEMD_ACTIVATION_UNIT not set")
		os.Exit(1)
	}

	target := os.Args[1]
	if err := updateSecrets(serviceName, target); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
