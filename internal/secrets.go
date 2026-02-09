package internal

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

func ParseServiceSecrets(path string) (map[string]interface{}, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("Cannot read json file '%s': %w", path, err)
	}
	var data map[string]interface{}
	err = json.Unmarshal(content, &data)
	if err != nil {
		return nil, fmt.Errorf("Cannot parse '%s' as json file: %w", path, err)
	}
	for key, val := range data {
		val, ok := val.(string)
		if ok && strings.HasPrefix(val, "base64:") {
			val = strings.TrimPrefix(val, "base64:")
			val, err := base64.StdEncoding.DecodeString(val)
			if err != nil {
				return nil, fmt.Errorf("Cannot decode '%s' as base64 value: %w", val, err)
			}
			data[key] = val
		}
	}
	return data, err
}

func IsEnvironmentFile(secret string) bool {
	return strings.HasSuffix(secret, ".service.EnvironmentFile")
}
