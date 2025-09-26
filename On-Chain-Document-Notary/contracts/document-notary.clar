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

(define-read-only (get-document-info (document-hash (buff 32)))
  (match (map-get? notarized-documents document-hash)
    document
    (some {
      owner: (get owner document),
      timestamp: (get timestamp document),
      description: (get description document),
      document-type: (get document-type document),
      witness-count: (get witness-count document),
      signatures-received: (get signatures-received document),
      verified: (get verified document),
      verification-level: (get verification-level document),
      expired: (>= block-height (get expiry-height document)),
      fee-paid: (get notary-fee document)
    })
    none))

(define-read-only (get-document-witnesses (document-hash (buff 32)))
  (match (map-get? notarized-documents document-hash)
    document (some (get witnesses document))
    none))

(define-read-only (get-witness-signatures (document-hash (buff 32)))
  (match (map-get? notarized-documents document-hash)
    document (some (get witness-signatures document))
    none))

(define-read-only (get-user-document (user principal) (doc-id uint))
  (map-get? user-documents {user: user, doc-id: doc-id}))

(define-read-only (get-user-document-count (user principal))
  (default-to u0 (map-get? user-doc-counter user)))

(define-read-only (verify-document-authenticity (document-hash (buff 32)))
  (let ((document (map-get? notarized-documents document-hash)))
    (match document
      doc-data
      {
        exists: true,
        timestamp: (get timestamp doc-data),
        owner: (get owner doc-data),
        verified: (get verified doc-data),
        verification-level: (get verification-level doc-data),
        witness-count: (get witness-count doc-data),
        signatures-received: (get signatures-received doc-data),
        expired: (>= block-height (get expiry-height doc-data)),
        document-type: (get document-type doc-data)
      }
      {
        exists: false,
        timestamp: u0,
        owner: 'SP000000000000000000002Q6VF78,
        verified: false,
        verification-level: u0,
        witness-count: u0,
        signatures-received: u0,
        expired: true,
        document-type: u0
      })))

(define-read-only (get-contract-stats)
  {
    total-documents: (var-get total-documents-notarized),
    base-fee: (var-get base-notary-fee),
    witness-fee: (var-get witness-fee),
    verification-fee: (var-get verification-fee),
    contract-active: (var-get contract-active),
    emergency-pause: (var-get emergency-pause)
  })

(define-read-only (calculate-notarization-cost 
  (document-type uint) 
  (witness-count uint))
  (let ((type-multiplier (get-type-fee-multiplier document-type)))
    (+ (* (var-get base-notary-fee) type-multiplier)
       (* (var-get witness-fee) witness-count))))


(define-public (add-authorized-notary (notary principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-notaries notary {
      active: true,
      total-notarizations: u0,
      reputation-score: u100,
      join-date: block-height
    }))))

(define-public (remove-authorized-notary (notary principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-delete authorized-notaries notary))))

(define-public (update-fees 
  (new-base-fee uint) 
  (new-witness-fee uint) 
  (new-verification-fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> new-base-fee u0) err-invalid-fee)
    (asserts! (> new-witness-fee u0) err-invalid-fee)
    (asserts! (> new-verification-fee u0) err-invalid-fee)
    
    (var-set base-notary-fee new-base-fee)
    (var-set witness-fee new-witness-fee)
    (var-set verification-fee new-verification-fee)
    (ok true)))

(define-public (emergency-pause-contract)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set emergency-pause true)
    (ok true)))

(define-public (resume-contract)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set emergency-pause false)
    (ok true)))

(define-public (withdraw-earnings (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (let ((current-earnings (default-to u0 (map-get? notary-earnings contract-owner))))
      (asserts! (>= current-earnings amount) err-insufficient-funds)
      (map-set notary-earnings contract-owner (- current-earnings amount))
      (stx-transfer? amount (as-contract tx-sender) tx-sender))))

(define-public (log-document-access (document-hash (buff 32)))
  (let ((caller tx-sender)
        (current-log (default-to {access-count: u0, last-access: u0}
                                (map-get? document-access-log 
                                         {document-hash: document-hash, accessor: caller}))))
    (ok (map-set document-access-log 
                 {document-hash: document-hash, accessor: caller}
                 {
                   access-count: (+ (get access-count current-log) u1),
                   last-access: block-height
                 }))))

;; Private helper functions
(define-private (get-type-fee-multiplier (doc-type uint))
  (if (is-eq doc-type doc-type-legal) u3
  (if (is-eq doc-type doc-type-financial) u2
  (if (is-eq doc-type doc-type-medical) u2
  (if (is-eq doc-type doc-type-academic) u1
  (if (is-eq doc-type doc-type-business) u2
      u1)))))) ;; personal and default

(define-private (register-witness-entry (witness principal))
  (let ((current-witness (default-to {total-witnessed: u0, reputation: u100, active: true}
                                    (map-get? witness-registry witness))))
    (map-set witness-registry witness
             (merge current-witness {active: true}))
    witness))

(define-private (update-witness-stats (witness principal))
  (let ((current-stats (default-to {total-witnessed: u0, reputation: u100, active: true}
                                  (map-get? witness-registry witness))))
    (map-set witness-registry witness
             {
               total-witnessed: (+ (get total-witnessed current-stats) u1),
               reputation: (min (+ (get reputation current-stats) u1) u1000),
               active: true
             })))