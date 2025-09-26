# On-Chain Document Notary

A blockchain-based document notarization service that provides cryptographic proof of document authenticity and timestamp verification.

## Features

- **Document Hashing**: Secure storage of document hashes with timestamp proof
- **Witness System**: Multi-party witness verification for enhanced authenticity
- **Fee Structure**: Transparent pricing for notarization services
- **Ownership Tracking**: Complete document ownership and history management
- **Public Verification**: Anyone can verify document authenticity
- **Earnings Management**: Revenue tracking for notary services

## Contract Functions

### Public Functions
- `notarize-document()`: Create notarized record of document hash
- `add-witness-signature()`: Add witness verification to document
- `verify-document()`: Admin verification of document authenticity

### Read-Only Functions
- `get-document-info()`: Retrieve complete document details
- `get-user-document()`: Get user's document by ID
- `verify-document-authenticity()`: Public verification interface

## Usage

Users submit document hashes with witness lists, pay notarization fees, and receive cryptographic proof of document existence and authenticity.

## Security

Only document hashes are stored on-chain, ensuring privacy while maintaining verifiability through cryptographic proof.