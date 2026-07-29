package internal

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

// ParseServiceSecrets reads a service secret json file. String values
// prefixed with "base64:" are decoded to []byte to support binary secrets.
func ParseServiceSecrets(path string) (map[string]interface{}, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("cannot read json file '%s': %w", path, err)
	}
	var data map[string]interface{}
	if err := json.Unmarshal(content, &data); err != nil {
		return nil, fmt.Errorf("cannot parse '%s' as json file: %w", path, err)
	}
	for key, val := range data {
		s, ok := val.(string)
		if !ok || !strings.HasPrefix(s, "base64:") {
			continue
		}
		decoded, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(s, "base64:"))
		if err != nil {
			return nil, fmt.Errorf("cannot decode secret '%s' in '%s' as base64: %w", key, path, err)
		}
		data[key] = decoded
	}
	return data, nil
}

func IsEnvironmentFile(secret string) bool {
	return strings.HasSuffix(secret, ".service.EnvironmentFile")
}

// SecretBytes returns the byte representation of a secret value as stored in
// the map returned by ParseServiceSecrets.
func SecretBytes(val interface{}) []byte {
	switch v := val.(type) {
	case []byte:
		return v
	case string:
		return []byte(v)
	default:
		return []byte(fmt.Sprint(v))
	}
}
