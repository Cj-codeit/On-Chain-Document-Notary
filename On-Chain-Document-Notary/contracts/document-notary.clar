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