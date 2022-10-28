package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

func parseServiceSecrets(path string) (map[string]interface{}, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("Cannot read json file '%s': %w", path, err)
	}
	var data map[string]interface{}
	err = json.Unmarshal(content, &data)
	if err != nil {
		return nil, fmt.Errorf("Cannot parse '%s' as json file: %w", path, err)
	}
	return data, nil
}

func isEnvironmentFile(secret string) bool {
	return strings.HasSuffix(secret, ".service.EnvironmentFile")
}
