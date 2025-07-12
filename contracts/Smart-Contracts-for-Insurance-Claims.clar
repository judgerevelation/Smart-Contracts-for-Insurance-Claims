(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-CLAIM-NOT-FOUND (err u102))
(define-constant ERR-CLAIM-ALREADY-PROCESSED (err u103))
(define-constant ERR-INSUFFICIENT-BALANCE (err u104))
(define-constant ERR-EMERGENCY-LIMIT-EXCEEDED (err u105))

(define-data-var contract-owner principal tx-sender)
(define-data-var total-claims uint u0)
(define-data-var emergency-claim-limit uint u10000)

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
