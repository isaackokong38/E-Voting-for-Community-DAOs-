(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-VOTE-CLOSED (err u101))
(define-constant ERR-ALREADY-VOTED (err u102))
(define-constant ERR-INVALID-VOTE (err u103))
(define-constant ERR-NO-ACTIVE-PROPOSAL (err u104))
(define-constant ERR-CANNOT-DELEGATE-TO-SELF (err u105))
(define-constant ERR-DELEGATE-NOT-REGISTERED (err u106))
(define-constant ERR-DELEGATION-EXISTS (err u107))
(define-constant ERR-NO-DELEGATION (err u108))

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

;; Delegation mapping: delegator -> delegate for specific proposals
(define-map ProposalDelegations
  { delegator: principal, proposal-id: uint }
  { delegate: principal, delegation-block: uint }
)

;; Track delegation power per delegate per proposal
(define-map DelegationPower
  { delegate: principal, proposal-id: uint }
  { total-power: uint }
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

;; === DELEGATION FUNCTIONS ===

;; Delegate voting power to another registered voter for a specific proposal
(define-public (delegate-vote (proposal-id uint) (delegate principal))
  (let ((proposal (unwrap! (map-get? Proposals { proposal-id: proposal-id }) ERR-NO-ACTIVE-PROPOSAL)))
    (begin
      ;; Ensure delegator is registered voter
      (asserts! (is-some (map-get? VoterRegistry { address: tx-sender })) ERR-NOT-AUTHORIZED)
      ;; Ensure delegate is registered voter  
      (asserts! (is-some (map-get? VoterRegistry { address: delegate })) ERR-DELEGATE-NOT-REGISTERED)
      ;; Cannot delegate to self
      (asserts! (not (is-eq tx-sender delegate)) ERR-CANNOT-DELEGATE-TO-SELF)
      ;; Proposal must be active
      (asserts! (< stacks-block-height (get end-block proposal)) ERR-VOTE-CLOSED)
      ;; Cannot delegate if already voted directly
      (asserts! (is-none (map-get? Voters { voter: tx-sender, proposal-id: proposal-id })) ERR-ALREADY-VOTED)
      ;; Cannot delegate if delegation already exists
      (asserts! (is-none (map-get? ProposalDelegations { delegator: tx-sender, proposal-id: proposal-id })) ERR-DELEGATION-EXISTS)
      
      ;; Store delegation
      (map-set ProposalDelegations 
        { delegator: tx-sender, proposal-id: proposal-id }
        { delegate: delegate, delegation-block: stacks-block-height })
      
      ;; Update delegation power
      (let ((current-power (default-to u0 (get total-power (map-get? DelegationPower { delegate: delegate, proposal-id: proposal-id })))))
        (map-set DelegationPower
          { delegate: delegate, proposal-id: proposal-id }
          { total-power: (+ current-power u1) })
        (ok true)))))

;; Revoke delegation for a specific proposal
(define-public (revoke-delegation (proposal-id uint))
  (let ((delegation (unwrap! (map-get? ProposalDelegations { delegator: tx-sender, proposal-id: proposal-id }) ERR-NO-DELEGATION))
        (proposal (unwrap! (map-get? Proposals { proposal-id: proposal-id }) ERR-NO-ACTIVE-PROPOSAL)))
    (begin
      ;; Proposal must still be active
      (asserts! (< stacks-block-height (get end-block proposal)) ERR-VOTE-CLOSED)
      
      ;; Remove delegation
      (map-delete ProposalDelegations { delegator: tx-sender, proposal-id: proposal-id })
      
      ;; Update delegation power
      (let ((delegate (get delegate delegation))
            (current-power (default-to u0 (get total-power (map-get? DelegationPower { delegate: delegate, proposal-id: proposal-id })))))
        (if (> current-power u0)
          (map-set DelegationPower
            { delegate: delegate, proposal-id: proposal-id }
            { total-power: (- current-power u1) })
          (map-delete DelegationPower { delegate: delegate, proposal-id: proposal-id })))
      (ok true))))

;; Cast vote as delegate (includes own vote + delegated votes)
(define-public (cast-delegated-vote (proposal-id uint) (vote bool))
  (let ((proposal (unwrap! (map-get? Proposals { proposal-id: proposal-id }) ERR-NO-ACTIVE-PROPOSAL))
        (delegation-power (default-to u0 (get total-power (map-get? DelegationPower { delegate: tx-sender, proposal-id: proposal-id })))))
    (begin
      ;; Ensure delegate is registered voter
      (asserts! (is-some (map-get? VoterRegistry { address: tx-sender })) ERR-NOT-AUTHORIZED)
      ;; Proposal must be active
      (asserts! (< stacks-block-height (get end-block proposal)) ERR-VOTE-CLOSED)
      ;; Cannot vote if already voted directly
      (asserts! (is-none (map-get? Voters { voter: tx-sender, proposal-id: proposal-id })) ERR-ALREADY-VOTED)
      
      ;; Record that delegate has voted (prevents double voting)
      (map-set Voters { voter: tx-sender, proposal-id: proposal-id } { voted: true })
      
      ;; Calculate total voting power (own vote + delegated votes)
      (let ((total-votes (+ u1 delegation-power)))
        (if vote
          (map-set Proposals { proposal-id: proposal-id }
            (merge proposal { yes-votes: (+ (get yes-votes proposal) total-votes) }))
          (map-set Proposals { proposal-id: proposal-id }
            (merge proposal { no-votes: (+ (get no-votes proposal) total-votes) })))
        (ok total-votes)))))

;; === READ-ONLY DELEGATION FUNCTIONS ===

;; Get delegation info for a voter on specific proposal
(define-read-only (get-delegation (delegator principal) (proposal-id uint))
  (map-get? ProposalDelegations { delegator: delegator, proposal-id: proposal-id }))

;; Get total delegation power for a delegate on specific proposal
(define-read-only (get-delegation-power (delegate principal) (proposal-id uint))
  (default-to u0 (get total-power (map-get? DelegationPower { delegate: delegate, proposal-id: proposal-id }))))

;; Check if voter has delegated for a specific proposal
(define-read-only (has-delegated (voter principal) (proposal-id uint))
  (is-some (map-get? ProposalDelegations { delegator: voter, proposal-id: proposal-id })))
