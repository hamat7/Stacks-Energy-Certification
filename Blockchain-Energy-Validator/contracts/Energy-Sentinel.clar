;; Energy Certification Smart Contract
;; Manages certification of energy production and producers

(define-constant contract-administrator tx-sender)

;; Error Constants
(define-constant ERR-UNAUTHORIZED-ACCESS (err u200))
(define-constant ERR-NOT-CERTIFIED (err u201))
(define-constant ERR-ALREADY-CERTIFIED (err u202))
(define-constant ERR-INVALID-CERTIFIER (err u203))
(define-constant ERR-INVALID-PRODUCTION-AMOUNT (err u204))
(define-constant ERR-UNAUTHORIZED-ACTION (err u205))
(define-constant ERR-INVALID-FEE (err u206))
(define-constant ERR-INVALID-MINIMUM-PRODUCTION (err u207))
(define-constant ERR-INVALID-INPUT-STRING (err u208))
(define-constant ERR-INVALID-REVOCATION-REASON (err u209))

;; Configuration Variables
(define-data-var certification-processing-fee uint u1000)
(define-data-var minimum-energy-production uint u100)
(define-data-var maximum-certification-fee uint u1000000)
(define-data-var maximum-production-limit uint u1000000)

;; Data Maps
(define-map certified-energy-producers principal bool)
(define-map authorized-certification-entities principal bool)
(define-map energy-production-records
    principal
    {
        total-energy-output: uint,
        certification-timestamp: uint,
        energy-generation-type: (string-ascii 20),
        is-currently-certified: bool,
        revocation-details: {
            reason: (optional (string-ascii 50)),
            timestamp: (optional uint),
            revoked-by: (optional principal)
        }
    })

;; Validation Helpers
(define-private (is-valid-certification-entity (potential-certifier principal))
    (default-to false (map-get? authorized-certification-entities potential-certifier)))

(define-private (validate-input-string (input (string-ascii 20)))
    (let ((string-length (len input)))
        (and (> string-length u0) (<= string-length u20))))

(define-private (validate-revocation-explanation (explanation (string-ascii 50)))
    (let ((string-length (len explanation)))
        (and (> string-length u0) (<= string-length u50))))

(define-private (can-revoke-energy-certification (requester principal))
    (or 
        (is-eq requester contract-administrator)
        (is-valid-certification-entity requester)))

;; Administrator Management Functions
(define-public (register-certification-entity (certification-entity principal))
    (begin
        (asserts! (is-eq tx-sender contract-administrator) ERR-UNAUTHORIZED-ACCESS)
        (asserts! 
            (and 
                (not (is-eq certification-entity contract-administrator))
                (not (default-to false (map-get? authorized-certification-entities certification-entity)))
            ) 
            ERR-INVALID-CERTIFIER)
        (map-set authorized-certification-entities certification-entity true)
        (ok true)))

(define-public (remove-certification-entity (certification-entity principal))
    (begin
        (asserts! (is-eq tx-sender contract-administrator) ERR-UNAUTHORIZED-ACCESS)
        (asserts! 
            (and 
                (not (is-eq certification-entity contract-administrator))
                (default-to false (map-get? authorized-certification-entities certification-entity))
            ) 
            ERR-INVALID-CERTIFIER)
        (map-delete authorized-certification-entities certification-entity)
        (ok true)))

;; Energy Certification Workflow
(define-public (request-energy-certification 
                (energy-output uint) 
                (energy-generation-type (string-ascii 20)))
    (let (
        (current-producer-record 
            (default-to 
                {
                    total-energy-output: u0,
                    certification-timestamp: u0,
                    energy-generation-type: "",
                    is-currently-certified: false,
                    revocation-details: {
                        reason: none,
                        timestamp: none,
                        revoked-by: none
                    }
                }
                (map-get? energy-production-records tx-sender)))
    )
        (asserts! 
            (and 
                (>= energy-output (var-get minimum-energy-production))
                (<= energy-output (var-get maximum-production-limit))
            ) 
            ERR-INVALID-PRODUCTION-AMOUNT)
        
        (asserts! (validate-input-string energy-generation-type) ERR-INVALID-INPUT-STRING)
        (asserts! (not (get is-currently-certified current-producer-record)) ERR-ALREADY-CERTIFIED)
        
        (map-set energy-production-records tx-sender
            {
                total-energy-output: energy-output,
                certification-timestamp: block-height,
                energy-generation-type: energy-generation-type,
                is-currently-certified: false,
                revocation-details: {
                    reason: none,
                    timestamp: none,
                    revoked-by: none
                }
            })
        (ok true)))

(define-public (approve-energy-certification (energy-producer principal))
    (let (
        (producer-record 
            (default-to 
                {
                    total-energy-output: u0,
                    certification-timestamp: u0,
                    energy-generation-type: "",
                    is-currently-certified: false,
                    revocation-details: {
                        reason: none,
                        timestamp: none,
                        revoked-by: none
                    }
                }
                (map-get? energy-production-records energy-producer)))
    )
        (asserts! (is-valid-certification-entity tx-sender) ERR-INVALID-CERTIFIER)
        (asserts! (not (get is-currently-certified producer-record)) ERR-ALREADY-CERTIFIED)
        (asserts! (> (get total-energy-output producer-record) u0) ERR-INVALID-PRODUCTION-AMOUNT)
        
        (map-set energy-production-records energy-producer
            {
                total-energy-output: (get total-energy-output producer-record),
                certification-timestamp: block-height,
                energy-generation-type: (get energy-generation-type producer-record),
                is-currently-certified: true,
                revocation-details: {
                    reason: none,
                    timestamp: none,
                    revoked-by: none
                }
            })
        (map-set certified-energy-producers energy-producer true)
        (ok true)))

(define-public (revoke-energy-certification 
                (energy-producer principal) 
                (revocation-reason (string-ascii 50)))
    (begin
        (asserts! (can-revoke-energy-certification tx-sender) ERR-UNAUTHORIZED-ACTION)
        (asserts! 
            (default-to false (map-get? certified-energy-producers energy-producer)) 
            ERR-NOT-CERTIFIED)
        (asserts! (validate-revocation-explanation revocation-reason) ERR-INVALID-REVOCATION-REASON)
        
        (let (
            (producer-record 
                (unwrap! 
                    (map-get? energy-production-records energy-producer) 
                    ERR-NOT-CERTIFIED))
        )
            (map-set energy-production-records energy-producer
                {
                    total-energy-output: (get total-energy-output producer-record),
                    certification-timestamp: (get certification-timestamp producer-record),
                    energy-generation-type: (get energy-generation-type producer-record),
                    is-currently-certified: false,
                    revocation-details: {
                        reason: (some revocation-reason),
                        timestamp: (some block-height),
                        revoked-by: (some tx-sender)
                    }
                })
            (map-delete certified-energy-producers energy-producer)
            (ok true))))

;; Read-Only Utility Functions
(define-read-only (check-energy-producer-certification (energy-producer principal))
    (ok (default-to false (map-get? certified-energy-producers energy-producer))))

(define-read-only (retrieve-energy-producer-record (energy-producer principal))
    (ok (default-to
        {
            total-energy-output: u0,
            certification-timestamp: u0,
            energy-generation-type: "",
            is-currently-certified: false,
            revocation-details: {
                reason: none,
                timestamp: none,
                revoked-by: none
            }
        }
        (map-get? energy-production-records energy-producer))))

(define-read-only (get-current-certification-fee)
    (ok (var-get certification-processing-fee)))

;; Administrative Configuration Functions
(define-public (update-certification-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-administrator) ERR-UNAUTHORIZED-ACCESS)
        (asserts! 
            (and 
                (> new-fee u0)
                (<= new-fee (var-get maximum-certification-fee))
            ) 
            ERR-INVALID-FEE)
        (var-set certification-processing-fee new-fee)
        (ok true)))

(define-public (update-minimum-production-requirement (new-minimum-production uint))
    (begin
        (asserts! (is-eq tx-sender contract-administrator) ERR-UNAUTHORIZED-ACCESS)
        (asserts! 
            (and 
                (> new-minimum-production u0)
                (<= new-minimum-production (var-get maximum-production-limit))
            ) 
            ERR-INVALID-MINIMUM-PRODUCTION)
        (var-set minimum-energy-production new-minimum-production)
        (ok true)))