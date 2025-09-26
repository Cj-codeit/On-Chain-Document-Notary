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

(define-public (notarize-document 
  (document-hash (buff 32))
  (description (string-ascii 512))
  (document-type uint)
  (witnesses (list 10 principal))
  (expiry-blocks uint)
  (metadata (string-ascii 256)))
  (let ((caller tx-sender)
        (witness-count (len witnesses))
        (type-multiplier (get-type-fee-multiplier document-type))
        (total-fee (+ (* (var-get base-notary-fee) type-multiplier) 
                     (* (var-get witness-fee) witness-count)))
        (doc-id (default-to u0 (map-get? user-doc-counter caller)))
        (expiry-height (+ block-height expiry-blocks)))
    
    ;; Validation checks
    (asserts! (var-get contract-active) err-unauthorized)
    (asserts! (not (var-get emergency-pause)) err-unauthorized)
    (asserts! (is-none (map-get? notarized-documents document-hash)) err-already-exists)
    (asserts! (>= (stx-get-balance caller) total-fee) err-insufficient-funds)
    (asserts! (<= witness-count max-witnesses) err-invalid-witness)
    (asserts! (<= doc-id max-user-documents) err-max-documents-reached)
    (asserts! (and (>= document-type u1) (<= document-type u6)) err-not-found)
    (asserts! (> expiry-blocks u0) err-document-expired)
    
    ;; Process payment
    (try! (stx-transfer? total-fee caller contract-owner))
    
    ;; Create witness signature tracking list
    (let ((witness-sigs (list false false false false false false false false false false)))
      ;; Store document
      (map-set notarized-documents document-hash {
        owner: caller,
        document-hash: document-hash,
        timestamp: block-height,
        description: description,
        document-type: document-type,
        witnesses: witnesses,
        witness-signatures: witness-sigs,
        witness-count: witness-count,
        signatures-received: u0,
        notary-fee: total-fee,
        expiry-height: expiry-height,
        verified: false,
        verification-level: u0,
        metadata: metadata
      }))
    
    ;; Update user document tracking
    (map-set user-documents 
      {user: caller, doc-id: (+ doc-id u1)}
      document-hash)
    (map-set user-doc-counter caller (+ doc-id u1))
    
    ;; Update earnings and statistics
    (let ((current-earnings (default-to u0 (map-get? notary-earnings contract-owner))))
      (map-set notary-earnings contract-owner (+ current-earnings total-fee)))
    
    (var-set total-documents-notarized (+ (var-get total-documents-notarized) u1))
    
    ;; Initialize witness registry entries
    (map witnesses register-witness-entry)
    
    (ok document-hash)))

(define-public (add-witness-signature 
  (document-hash (buff 32))
  (signature-data (buff 64)))
  (let ((caller tx-sender)
        (document (unwrap! (map-get? notarized-documents document-hash) err-not-found)))
    
    ;; Validation
    (asserts! (< block-height (get expiry-height document)) err-document-expired)
    (asserts! (is-some (index-of (get witnesses document) caller)) err-invalid-witness)
    
    ;; Check if witness already signed
    (let ((witness-index (unwrap! (index-of (get witnesses document) caller) err-invalid-witness))
          (current-sigs (get witness-signatures document)))
      (asserts! (not (unwrap! (element-at current-sigs witness-index) err-invalid-signature)) 
                err-witness-already-signed)
      
      ;; Update signature status
      (let ((updated-sigs (replace-at current-sigs witness-index true))
            (new-sig-count (+ (get signatures-received document) u1)))
        
        (map-set notarized-documents document-hash
          (merge document {
            witness-signatures: updated-sigs,
            signatures-received: new-sig-count,
            verified: (>= new-sig-count (/ (get witness-count document) u2))
          }))
        
        ;; Update witness registry
        (update-witness-stats caller)
        
        (ok true)))))

(define-public (verify-document-by-notary 
  (document-hash (buff 32))
  (verification-level uint))
  (let ((document (unwrap! (map-get? notarized-documents document-hash) err-not-found)))
    (asserts! (or (is-eq tx-sender contract-owner)
                  (is-some (map-get? authorized-notaries tx-sender))) err-unauthorized)
    (asserts! (< block-height (get expiry-height document)) err-document-expired)
    (asserts! (<= verification-level u3) err-not-found)
    
    ;; Charge verification fee
    (try! (stx-transfer? (var-get verification-fee) tx-sender contract-owner))
    
    (ok (map-set notarized-documents document-hash
      (merge document {
        verified: true,
        verification-level: verification-level
      })))))
