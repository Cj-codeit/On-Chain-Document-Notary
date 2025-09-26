;; ========================================
;; SECTION 1: CONTRACT INITIALIZATION & CONSTANTS
;; ========================================

;; On-Chain Document Notary
;; Enhanced document timestamping, notarization, and verification service

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-invalid-witness (err u104))
(define-constant err-insufficient-funds (err u105))
(define-constant err-invalid-fee (err u106))
(define-constant err-document-expired (err u107))
(define-constant err-max-documents-reached (err u108))
(define-constant err-invalid-signature (err u109))
(define-constant err-witness-already-signed (err u110))

;; Document types
(define-constant doc-type-legal u1)
(define-constant doc-type-financial u2)
(define-constant doc-type-academic u3)
(define-constant doc-type-medical u4)
(define-constant doc-type-business u5)
(define-constant doc-type-personal u6)

;; Maximum limits
(define-constant max-witnesses u10)
(define-constant max-user-documents u100)
(define-constant max-description-length u512)

(define-map notarized-documents
  (buff 32)
  {
    owner: principal,
    document-hash: (buff 32),
    timestamp: uint,
    description: (string-ascii 512),
    document-type: uint,
    witnesses: (list 10 principal),
    witness-signatures: (list 10 bool),
    witness-count: uint,
    signatures-received: uint,
    notary-fee: uint,
    expiry-height: uint,
    verified: bool,
    verification-level: uint,
    metadata: (string-ascii 256)
  })

(define-map user-documents
  { user: principal, doc-id: uint }
  (buff 32))

(define-map user-doc-counter
  principal
  uint)

(define-map notary-earnings
  principal
  uint)

(define-map authorized-notaries
  principal
  {
    active: bool,
    total-notarizations: uint,
    reputation-score: uint,
    join-date: uint
  })

(define-map document-access-log
  { document-hash: (buff 32), accessor: principal }
  {
    access-count: uint,
    last-access: uint
  })

(define-map witness-registry
  principal
  {
    total-witnessed: uint,
    reputation: uint,
    active: bool
  })

;; Configuration variables
(define-data-var base-notary-fee uint u1000)
(define-data-var witness-fee uint u100)
(define-data-var verification-fee uint u500)
(define-data-var contract-active bool true)
(define-data-var total-documents-notarized uint u0)
(define-data-var emergency-pause bool false)