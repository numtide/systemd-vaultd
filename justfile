default:
    @just --list

# Format and lint project
fmt:
    treefmt

# Build the project
build:
    go build .

# Run unitests
test:
     pytest -s ./tests
