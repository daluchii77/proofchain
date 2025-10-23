;; Proof Chain - Decentralized Document & IP Timestamping Service
;; A production-ready smart contract for immutable proof of existence and ownership

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u1100))
(define-constant err-not-found (err u1101))
(define-constant err-unauthorized (err u1102))
(define-constant err-already-exists (err u1103))
(define-constant err-invalid-hash (err u1104))
(define-constant err-not-verifier (err u1105))
(define-constant err-already-verified (err u1106))
(define-constant err-transfer-failed (err u1107))

;; Minimum registration fee
(define-constant min-registration-fee u100000)

;; Data Variables
(define-data-var proof-nonce uint u0)
(define-data-var total-proofs uint u0)
(define-data-var total-verified uint u0)
(define-data-var platform-revenue uint u0)
(define-data-var registration-fee uint u1000000)

;; Proof of Existence Record
(define-map proofs
    (buff 32)
    {
        owner: principal,
        document-hash: (buff 32),
        metadata: (string-utf8 200),
        timestamp: uint,
        is-public: bool,
        is-verified: bool,
        verifier: (optional principal),
        verification-date: (optional uint),
        category: (string-ascii 30)
    }
)

;; Owner's proof tracking
(define-map owner-proofs
    { owner: principal, index: uint }
    (buff 32)
)

(define-map owner-proof-count
    principal
    uint
)

;; Transfer history
(define-map proof-transfers
    { document-hash: (buff 32), index: uint }
    {
        from: principal,
        to: principal,
        transferred-at: uint
    }
)

(define-map transfer-count
    (buff 32)
    uint
)

;; Authorized verifiers
(define-map verifiers
    principal
    {
        name: (string-utf8 100),
        organization: (string-utf8 100),
        verified-count: uint,
        is-active: bool,
        added-at: uint
    }
)

;; Proof statistics
(define-map proof-stats
    principal
    {
        total-registered: uint,
        verified-proofs: uint,
        public-proofs: uint,
        private-proofs: uint
    }
)

;; Read-Only Functions

(define-read-only (get-proof (document-hash (buff 32)))
    (ok (map-get? proofs document-hash))
)

(define-read-only (verify-existence (document-hash (buff 32)))
    (ok (is-some (map-get? proofs document-hash)))
)

(define-read-only (get-proof-owner (document-hash (buff 32)))
    (match (map-get? proofs document-hash)
        proof (ok (some (get owner proof)))
        (ok none)
    )
)

(define-read-only (get-owner-proof-count (owner principal))
    (ok (default-to u0 (map-get? owner-proof-count owner)))
)

(define-read-only (get-owner-proof-hash (owner principal) (index uint))
    (ok (map-get? owner-proofs { owner: owner, index: index }))
)

(define-read-only (get-transfer-history (document-hash (buff 32)) (index uint))
    (ok (map-get? proof-transfers { document-hash: document-hash, index: index }))
)

(define-read-only (get-transfer-count (document-hash (buff 32)))
    (ok (default-to u0 (map-get? transfer-count document-hash)))
)

(define-read-only (get-verifier (verifier principal))
    (ok (map-get? verifiers verifier))
)

(define-read-only (get-proof-stats (owner principal))
    (ok (map-get? proof-stats owner))
)

(define-read-only (get-platform-stats)
    (ok {
        total-proofs: (var-get total-proofs),
        total-verified: (var-get total-verified),
        platform-revenue: (var-get platform-revenue),
        registration-fee: (var-get registration-fee)
    })
)

(define-read-only (get-registration-fee)
    (ok (var-get registration-fee))
)

;; Private Helper Functions

(define-private (add-to-owner-index (owner principal) (document-hash (buff 32)))
    (let (
        (current-count (default-to u0 (map-get? owner-proof-count owner)))
    )
        (map-set owner-proofs
            { owner: owner, index: current-count }
            document-hash
        )
        (map-set owner-proof-count owner (+ current-count u1))
    )
)

(define-private (update-proof-stats-register (owner principal) (is-public bool))
    (let (
        (stats (default-to 
            { total-registered: u0, verified-proofs: u0, public-proofs: u0, private-proofs: u0 }
            (map-get? proof-stats owner)))
    )
        (map-set proof-stats owner
            (merge stats {
                total-registered: (+ (get total-registered stats) u1),
                public-proofs: (if is-public (+ (get public-proofs stats) u1) (get public-proofs stats)),
                private-proofs: (if is-public (get private-proofs stats) (+ (get private-proofs stats) u1))
            })
        )
    )
)

(define-private (log-transfer (document-hash (buff 32)) (from principal) (to principal))
    (let (
        (current-count (default-to u0 (map-get? transfer-count document-hash)))
    )
        (map-set proof-transfers
            { document-hash: document-hash, index: current-count }
            {
                from: from,
                to: to,
                transferred-at: stacks-block-height
            }
        )
        (map-set transfer-count document-hash (+ current-count u1))
    )
)

;; Public Functions

;; Register proof of existence for a document
(define-public (register-proof
    (document-hash (buff 32))
    (metadata (string-utf8 200))
    (is-public bool)
    (category (string-ascii 30)))
    (let (
        (existing-proof (map-get? proofs document-hash))
        (fee (var-get registration-fee))
    )
        (asserts! (is-none existing-proof) err-already-exists)
        (asserts! (is-eq (len document-hash) u32) err-invalid-hash)
        
        ;; Pay registration fee
        (try! (stx-transfer? fee tx-sender contract-owner))
        
        ;; Create proof record
        (map-set proofs document-hash {
            owner: tx-sender,
            document-hash: document-hash,
            metadata: metadata,
            timestamp: stacks-block-height,
            is-public: is-public,
            is-verified: false,
            verifier: none,
            verification-date: none,
            category: category
        })
        
        ;; Add to owner index
        (add-to-owner-index tx-sender document-hash)
        
        ;; Update stats
        (update-proof-stats-register tx-sender is-public)
        
        ;; Update global stats
        (var-set proof-nonce (+ (var-get proof-nonce) u1))
        (var-set total-proofs (+ (var-get total-proofs) u1))
        (var-set platform-revenue (+ (var-get platform-revenue) fee))
        
        (ok document-hash)
    )
)

;; Transfer proof ownership
(define-public (transfer-proof (document-hash (buff 32)) (new-owner principal))
    (let (
        (proof (unwrap! (map-get? proofs document-hash) err-not-found))
    )
        (asserts! (is-eq tx-sender (get owner proof)) err-unauthorized)
        (asserts! (not (is-eq tx-sender new-owner)) err-unauthorized)
        
        ;; Update proof owner
        (map-set proofs document-hash
            (merge proof { owner: new-owner })
        )
        
        ;; Add to new owner's index
        (add-to-owner-index new-owner document-hash)
        
        ;; Log transfer
        (log-transfer document-hash tx-sender new-owner)
        
        (ok true)
    )
)

;; Add authorized verifier
(define-public (add-verifier
    (verifier principal)
    (name (string-utf8 100))
    (organization (string-utf8 100)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> (len name) u0) err-invalid-hash)
        
        (map-set verifiers verifier {
            name: name,
            organization: organization,
            verified-count: u0,
            is-active: true,
            added-at: stacks-block-height
        })
        
        (ok true)
    )
)

;; Verify a proof (verifier only)
(define-public (verify-proof (document-hash (buff 32)))
    (let (
        (proof (unwrap! (map-get? proofs document-hash) err-not-found))
        (verifier-info (unwrap! (map-get? verifiers tx-sender) err-not-verifier))
        (owner (get owner proof))
        (owner-stats (unwrap! (map-get? proof-stats owner) err-not-found))
    )
        (asserts! (get is-active verifier-info) err-not-verifier)
        (asserts! (not (get is-verified proof)) err-already-verified)
        
        ;; Update proof
        (map-set proofs document-hash
            (merge proof {
                is-verified: true,
                verifier: (some tx-sender),
                verification-date: (some stacks-block-height)
            })
        )
        
        ;; Update verifier stats
        (map-set verifiers tx-sender
            (merge verifier-info {
                verified-count: (+ (get verified-count verifier-info) u1)
            })
        )
        
        ;; Update owner stats
        (map-set proof-stats owner
            (merge owner-stats {
                verified-proofs: (+ (get verified-proofs owner-stats) u1)
            })
        )
        
        ;; Update global stats
        (var-set total-verified (+ (var-get total-verified) u1))
        
        (ok true)
    )
)

;; Update proof metadata
(define-public (update-metadata (document-hash (buff 32)) (new-metadata (string-utf8 200)))
    (let (
        (proof (unwrap! (map-get? proofs document-hash) err-not-found))
    )
        (asserts! (is-eq tx-sender (get owner proof)) err-unauthorized)
        (asserts! (> (len new-metadata) u0) err-invalid-hash)
        
        (map-set proofs document-hash
            (merge proof { metadata: new-metadata })
        )
        
        (ok true)
    )
)

;; Toggle proof visibility
(define-public (toggle-visibility (document-hash (buff 32)))
    (let (
        (proof (unwrap! (map-get? proofs document-hash) err-not-found))
        (owner (get owner proof))
        (current-public (get is-public proof))
        (owner-stats (unwrap! (map-get? proof-stats owner) err-not-found))
    )
        (asserts! (is-eq tx-sender owner) err-unauthorized)
        
        ;; Update proof
        (map-set proofs document-hash
            (merge proof { is-public: (not current-public) })
        )
        
        ;; Update stats
        (map-set proof-stats owner
            (merge owner-stats {
                public-proofs: (if current-public
                    (- (get public-proofs owner-stats) u1)
                    (+ (get public-proofs owner-stats) u1)),
                private-proofs: (if current-public
                    (+ (get private-proofs owner-stats) u1)
                    (- (get private-proofs owner-stats) u1))
            })
        )
        
        (ok (not current-public))
    )
)

;; Batch register multiple proofs (optimized)
(define-public (batch-register-proofs
    (hash1 (buff 32))
    (hash2 (buff 32))
    (hash3 (buff 32))
    (metadata (string-utf8 200))
    (is-public bool)
    (category (string-ascii 30)))
    (let (
        (fee (var-get registration-fee))
        (total-fee (* fee u3))
    )
        ;; Pay total fee once
        (try! (stx-transfer? total-fee tx-sender contract-owner))
        
        ;; Register all three proofs
        (try! (register-single-proof-internal hash1 metadata is-public category))
        (try! (register-single-proof-internal hash2 metadata is-public category))
        (try! (register-single-proof-internal hash3 metadata is-public category))
        
        (ok true)
    )
)

;; Internal function for batch operations (optimized)
(define-private (register-single-proof-internal
    (document-hash (buff 32))
    (metadata (string-utf8 200))
    (is-public bool)
    (category (string-ascii 30)))
    (let (
        (existing-proof (map-get? proofs document-hash))
    )
        (asserts! (is-none existing-proof) err-already-exists)
        (asserts! (is-eq (len document-hash) u32) err-invalid-hash)
        
        ;; Create proof record (no fee transfer here, done in parent)
        (map-set proofs document-hash {
            owner: tx-sender,
            document-hash: document-hash,
            metadata: metadata,
            timestamp: stacks-block-height,
            is-public: is-public,
            is-verified: false,
            verifier: none,
            verification-date: none,
            category: category
        })
        
        ;; Add to owner index
        (add-to-owner-index tx-sender document-hash)
        
        ;; Update stats
        (update-proof-stats-register tx-sender is-public)
        
        ;; Update global stats
        (var-set proof-nonce (+ (var-get proof-nonce) u1))
        (var-set total-proofs (+ (var-get total-proofs) u1))
        
        (ok true)
    )
)

;; Deactivate verifier
(define-public (deactivate-verifier (verifier principal))
    (let (
        (verifier-info (unwrap! (map-get? verifiers verifier) err-not-found))
    )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        
        (map-set verifiers verifier
            (merge verifier-info { is-active: false })
        )
        
        (ok true)
    )
)

;; Update registration fee
(define-public (update-registration-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (>= new-fee min-registration-fee) err-invalid-hash)
        
        (var-set registration-fee new-fee)
        (ok true)
    )
)

;; Withdraw platform revenue
(define-public (withdraw-revenue (amount uint))
    (let (
        (revenue (var-get platform-revenue))
    )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= amount revenue) err-invalid-hash)
        (asserts! (> amount u0) err-invalid-hash)
        
        (try! (as-contract (stx-transfer? amount tx-sender contract-owner)))
        (var-set platform-revenue (- revenue amount))
        
        (ok true)
    )
)