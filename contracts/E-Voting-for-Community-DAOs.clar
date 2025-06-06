(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-VOTE-CLOSED (err u101))
(define-constant ERR-ALREADY-VOTED (err u102))
(define-constant ERR-INVALID-VOTE (err u103))
(define-constant ERR-NO-ACTIVE-PROPOSAL (err u104))

(define-data-var admin principal tx-sender)
(define-data-var current-proposal-id uint u0)
(define-data-var total-proposals uint u0)

(define-map Proposals
  { proposal-id: uint }
  {
    creator: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    start-block: uint,
    end-block: uint,
    yes-votes: uint,
    no-votes: uint,
    status: (string-ascii 20)
  }
)

(define-map Voters 
  { voter: principal, proposal-id: uint } 
  { voted: bool }
)

(define-map VoterRegistry
  { address: principal }
  { verified: bool }
)

(define-public (initialize-contract)
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR-NOT-AUTHORIZED)
    (ok true)))

(define-public (register-voter (voter principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR-NOT-AUTHORIZED)
    (map-set VoterRegistry { address: voter } { verified: true })
    (ok true)))

(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)) (blocks uint))
  (let ((proposal-id (+ (var-get total-proposals) u1)))
    (begin
      (asserts! (is-some (map-get? VoterRegistry { address: tx-sender })) ERR-NOT-AUTHORIZED)
      (map-set Proposals
        { proposal-id: proposal-id }
        {
          creator: tx-sender,
          title: title,
          description: description,
          start-block: stacks-block-height,
          end-block: (+ stacks-block-height blocks),
          yes-votes: u0,
          no-votes: u0,
          status: "active"
        })
      (var-set total-proposals proposal-id)
      (var-set current-proposal-id proposal-id)
      (ok proposal-id))))

(define-public (cast-vote (proposal-id uint) (vote bool))
  (let ((proposal (unwrap! (map-get? Proposals { proposal-id: proposal-id }) ERR-NO-ACTIVE-PROPOSAL)))
    (begin
      (asserts! (is-some (map-get? VoterRegistry { address: tx-sender })) ERR-NOT-AUTHORIZED)
      (asserts! (< stacks-block-height (get end-block proposal)) ERR-VOTE-CLOSED)
      (asserts! (is-none (map-get? Voters { voter: tx-sender, proposal-id: proposal-id })) ERR-ALREADY-VOTED)
      
      (map-set Voters { voter: tx-sender, proposal-id: proposal-id } { voted: true })
      
      (if vote
        (map-set Proposals { proposal-id: proposal-id }
          (merge proposal { yes-votes: (+ (get yes-votes proposal) u1) }))
        (map-set Proposals { proposal-id: proposal-id }
          (merge proposal { no-votes: (+ (get no-votes proposal) u1) })))
      (ok true))))

(define-read-only (get-proposal (proposal-id uint))
  (map-get? Proposals { proposal-id: proposal-id }))

(define-read-only (get-voter-status (voter principal) (proposal-id uint))
  (map-get? Voters { voter: voter, proposal-id: proposal-id }))

(define-read-only (is-voter-registered (address principal))
  (is-some (map-get? VoterRegistry { address: address })))

(define-public (close-proposal (proposal-id uint))
  (let ((proposal (unwrap! (map-get? Proposals { proposal-id: proposal-id }) ERR-NO-ACTIVE-PROPOSAL)))
    (begin
      (asserts! (>= stacks-block-height (get end-block proposal)) ERR-VOTE-CLOSED)
      (map-set Proposals { proposal-id: proposal-id }
        (merge proposal { status: "completed" }))
      (ok true))))
