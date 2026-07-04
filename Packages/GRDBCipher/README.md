# GRDBCipher (local package)

MDE links GRDB against [SQLCipher](https://www.zetetic.net/sqlcipher/) for vault database encryption at rest (OQ-02).

## Setup

Clone GRDB sources into this folder (not committed — large vendor tree):

```bash
./scripts/setup-grdb-cipher.sh
```

This checks out GRDB `v7.11.1` and applies the SQLCipher-enabled `Package.swift` in this directory.

## Xcode

`mde.xcodeproj` references this folder as a **local Swift package** (`Packages/GRDBCipher`).
