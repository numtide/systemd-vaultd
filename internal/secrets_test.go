package internal

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestParseServiceSecrets(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "service.json")
	content := `{"foo": "bar", "blob": "base64:AAECvw==", "num": 42}`
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	data, err := ParseServiceSecrets(path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(SecretBytes(data["foo"]), []byte("bar")) {
		t.Errorf("unexpected value for foo: %v", data["foo"])
	}
	if !bytes.Equal(SecretBytes(data["blob"]), []byte{0x00, 0x01, 0x02, 0xbf}) {
		t.Errorf("base64 secret not decoded: %v", data["blob"])
	}
	if !bytes.Equal(SecretBytes(data["num"]), []byte("42")) {
		t.Errorf("unexpected value for num: %v", data["num"])
	}
}

func TestParseServiceSecretsInvalidBase64(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "service.json")
	if err := os.WriteFile(path, []byte(`{"foo": "base64:not-base64!"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := ParseServiceSecrets(path); err == nil {
		t.Error("expected error for invalid base64 value")
	}
}
