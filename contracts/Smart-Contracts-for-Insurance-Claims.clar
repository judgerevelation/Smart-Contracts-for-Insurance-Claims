(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-CLAIM-NOT-FOUND (err u102))
(define-constant ERR-CLAIM-ALREADY-PROCESSED (err u103))
(define-constant ERR-INSUFFICIENT-BALANCE (err u104))
(define-constant ERR-EMERGENCY-LIMIT-EXCEEDED (err u105))
(define-constant ERR-DISPUTE-NOT-FOUND (err u106))
(define-constant ERR-DISPUTE-ALREADY-EXISTS (err u107))
(define-constant ERR-INVALID-DISPUTE-STATUS (err u108))

(define-data-var contract-owner principal tx-sender)
(define-data-var total-claims uint u0)
(define-data-var emergency-claim-limit uint u10000)
(define-data-var total-disputes uint u0)

(define-map InsuranceClaims
    { claim-id: uint }
    {
        patient: principal,
        amount: uint,
        status: (string-ascii 20),
        verified: bool,
        processed-at: uint,
        medical-code: (string-ascii 10),
        is-emergency: bool,
    }
)

(define-map PatientBalances
    { patient: principal }
    { balance: uint }
)

(define-map DisputeResolution
    { dispute-id: uint }
    {
        claim-id: uint,
        patient: principal,
        reason: (string-ascii 100),
        status: (string-ascii 20),
        created-at: uint,
        resolved-at: uint,
        resolution-notes: (string-ascii 200),
    }
)

(define-public (submit-claim
        (amount uint)
        (medical-code (string-ascii 10))
    )
    (let ((claim-id (+ (var-get total-claims) u1)))
        (try! (validate-amount amount))
        (map-set InsuranceClaims { claim-id: claim-id } {
            patient: tx-sender,
            amount: amount,
            status: "PENDING",
            verified: false,
            processed-at: u0,
            medical-code: medical-code,
            is-emergency: false,
        })
        (var-set total-claims claim-id)
        (ok claim-id)
    )
)

(define-public (verify-claim (claim-id uint))
    (let ((claim (unwrap! (get-claim claim-id) ERR-CLAIM-NOT-FOUND)))
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (not (get verified claim)) ERR-CLAIM-ALREADY-PROCESSED)
        (map-set InsuranceClaims { claim-id: claim-id }
            (merge claim {
                verified: true,
                status: "VERIFIED",
            })
        )
        (ok true)
    )
)

(define-public (process-payment (claim-id uint))
    (let ((claim (unwrap! (get-claim claim-id) ERR-CLAIM-NOT-FOUND)))
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (get verified claim) ERR-NOT-AUTHORIZED)
        (map-set InsuranceClaims { claim-id: claim-id }
            (merge claim {
                status: "PAID",
                processed-at: stacks-block-height,
            })
        )
        (ok (add-to-balance (get patient claim) (get amount claim)))
    )
)

(define-public (withdraw-balance)
    (let (
            (balance-data (unwrap! (get-balance tx-sender) ERR-INSUFFICIENT-BALANCE))
            (amount (get balance balance-data))
        )
        (asserts! (> amount u0) ERR-INSUFFICIENT-BALANCE)
        (map-set PatientBalances { patient: tx-sender } { balance: u0 })
        (ok amount)
    )
)

(define-private (validate-amount (amount uint))
    (if (> amount u0)
        (ok true)
        ERR-INVALID-AMOUNT
    )
)

(define-private (is-contract-owner)
    (is-eq tx-sender (var-get contract-owner))
)

(define-private (get-claim (claim-id uint))
    (map-get? InsuranceClaims { claim-id: claim-id })
)

(define-private (get-balance (patient principal))
    (map-get? PatientBalances { patient: patient })
)

(define-private (add-to-balance
        (patient principal)
        (amount uint)
    )
    (let ((current-balance (default-to { balance: u0 } (get-balance patient))))
        (map-set PatientBalances { patient: patient } { balance: (+ (get balance current-balance) amount) })
        true
    )
)

(define-read-only (get-claim-details (claim-id uint))
    (ok (get-claim claim-id))
)

(define-read-only (get-patient-balance (patient principal))
    (ok (get-balance patient))
)

(define-public (submit-emergency-claim
        (amount uint)
        (medical-code (string-ascii 10))
    )
    (let ((claim-id (+ (var-get total-claims) u1)))
        (try! (validate-amount amount))
        (asserts! (<= amount (var-get emergency-claim-limit))
            ERR-EMERGENCY-LIMIT-EXCEEDED
        )
        (map-set InsuranceClaims { claim-id: claim-id } {
            patient: tx-sender,
            amount: amount,
            status: "EMERGENCY",
            verified: true,
            processed-at: stacks-block-height,
            medical-code: medical-code,
            is-emergency: true,
        })
        (var-set total-claims claim-id)
        (add-to-balance tx-sender amount)
        (ok claim-id)
    )
)

(define-public (set-emergency-limit (new-limit uint))
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (var-set emergency-claim-limit new-limit)
        (ok new-limit)
    )
)

(define-read-only (get-emergency-limit)
    (ok (var-get emergency-claim-limit))
)

(define-public (submit-dispute
        (claim-id uint)
        (reason (string-ascii 100))
    )
    (let (
            (claim (unwrap! (get-claim claim-id) ERR-CLAIM-NOT-FOUND))
            (dispute-id (+ (var-get total-disputes) u1))
        )
        (asserts! (is-eq (get patient claim) tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (is-none (get-dispute-by-claim claim-id)) ERR-DISPUTE-ALREADY-EXISTS)
        (map-set DisputeResolution { dispute-id: dispute-id } {
            claim-id: claim-id,
            patient: tx-sender,
            reason: reason,
            status: "OPEN",
            created-at: stacks-block-height,
            resolved-at: u0,
            resolution-notes: "",
        })
        (var-set total-disputes dispute-id)
        (ok dispute-id)
    )
)

(define-public (resolve-dispute
        (dispute-id uint)
        (approved bool)
        (resolution-notes (string-ascii 200))
    )
    (let ((dispute (unwrap! (get-dispute dispute-id) ERR-DISPUTE-NOT-FOUND)))
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status dispute) "OPEN") ERR-INVALID-DISPUTE-STATUS)
        (let ((new-status (if approved "APPROVED" "REJECTED")))
            (map-set DisputeResolution { dispute-id: dispute-id }
                (merge dispute {
                    status: new-status,
                    resolved-at: stacks-block-height,
                    resolution-notes: resolution-notes,
                })
            )
            (if approved
                (process-dispute-payment (get claim-id dispute))
                (ok true)
            )
        )
    )
)

(define-private (process-dispute-payment (claim-id uint))
    (let ((claim (unwrap! (get-claim claim-id) ERR-CLAIM-NOT-FOUND)))
        (map-set InsuranceClaims { claim-id: claim-id }
            (merge claim {
                status: "PAID",
                verified: true,
                processed-at: stacks-block-height,
            })
        )
        (ok (add-to-balance (get patient claim) (get amount claim)))
    )
)

(define-private (get-dispute (dispute-id uint))
    (map-get? DisputeResolution { dispute-id: dispute-id })
)

(define-private (get-dispute-by-claim (target-claim-id uint))
    (let ((dispute-1 (get-dispute u1))
          (dispute-2 (get-dispute u2))
          (dispute-3 (get-dispute u3))
          (dispute-4 (get-dispute u4))
          (dispute-5 (get-dispute u5)))
        (if (and (is-some dispute-1) (is-eq (get claim-id (unwrap-panic dispute-1)) target-claim-id))
            (some u1)
            (if (and (is-some dispute-2) (is-eq (get claim-id (unwrap-panic dispute-2)) target-claim-id))
                (some u2)
                (if (and (is-some dispute-3) (is-eq (get claim-id (unwrap-panic dispute-3)) target-claim-id))
                    (some u3)
                    (if (and (is-some dispute-4) (is-eq (get claim-id (unwrap-panic dispute-4)) target-claim-id))
                        (some u4)
                        (if (and (is-some dispute-5) (is-eq (get claim-id (unwrap-panic dispute-5)) target-claim-id))
                            (some u5)
                            none
                        )
                    )
                )
            )
        )
    )
)

(define-read-only (get-dispute-details (dispute-id uint))
    (ok (get-dispute dispute-id))
)

(define-read-only (get-claim-disputes (claim-id uint))
    (ok (get-dispute-by-claim claim-id))
)
