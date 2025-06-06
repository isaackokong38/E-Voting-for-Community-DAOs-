(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-VOTE-CLOSED (err u101))
(define-constant ERR-ALREADY-VOTED (err u102))
(define-constant ERR-INVALID-VOTE (err u103))
(define-constant ERR-NO-ACTIVE-PROPOSAL (err u104))
(define-constant ERR-PROPOSAL-EXISTS (err u105))

(define-data-var admin principal tx-sender)
(define-data-var current-proposal-id uint u0)
(define-data-var total-proposals uint u0)

(define-map Proposals
    uint 
    {
        title: (string-ascii 100),
        description: (string-ascii 500),
        creator: principal,
        start-block: uint,
        end-block: uint,
        yes-votes: uint,
        no-votes: uint,
        status: (string-ascii 20)
    }
)

(define-map Voters 
    { proposal-id: uint, voter: principal } 
    { vote: bool }
)

(define-map Members 
    principal 
    bool
)

(define-public (initialize-contract)
    (begin
        (asserts! (is-eq tx-sender (var-get admin)) ERR-NOT-AUTHORIZED)
        (ok true)
    )
)

(define-public (add-member (new-member principal))
    (begin
        (asserts! (is-eq tx-sender (var-get admin)) ERR-NOT-AUTHORIZED)
        (ok (map-set Members new-member true))
    )
)

(define-public (remove-member (member principal))
    (begin
        (asserts! (is-eq tx-sender (var-get admin)) ERR-NOT-AUTHORIZED)
        (ok (map-delete Members member))
    )
)

(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)) (blocks uint))
    (let
        (
            (proposal-id (+ (var-get total-proposals) u1))
            (start-block stacks-block-height)
            (end-block (+ stacks-block-height blocks))
        )
        (asserts! (is-some (map-get? Members tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (> blocks u0) ERR-INVALID-VOTE)
        (var-set total-proposals proposal-id)
        (var-set current-proposal-id proposal-id)
        (ok (map-set Proposals proposal-id {
            title: title,
            description: description,
            creator: tx-sender,
            start-block: start-block,
            end-block: end-block,
            yes-votes: u0,
            no-votes: u0,
            status: "active"
        }))
    )
)

(define-public (vote (proposal-id uint) (vote-bool bool))
    (let
        (
            (proposal (unwrap! (map-get? Proposals proposal-id) ERR-NO-ACTIVE-PROPOSAL))
            (voter-key { proposal-id: proposal-id, voter: tx-sender })
        )
        (asserts! (is-some (map-get? Members tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (not (is-some (map-get? Voters voter-key))) ERR-ALREADY-VOTED)
        (asserts! (< stacks-block-height (get end-block proposal)) ERR-VOTE-CLOSED)
        (map-set Voters voter-key { vote: vote-bool })
        (if vote-bool
            (map-set Proposals proposal-id (merge proposal { yes-votes: (+ (get yes-votes proposal) u1) }))
            (map-set Proposals proposal-id (merge proposal { no-votes: (+ (get no-votes proposal) u1) }))
        )
        (ok true)
    )
)

(define-read-only (get-proposal (proposal-id uint))
    (map-get? Proposals proposal-id)
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
    (map-get? Voters { proposal-id: proposal-id, voter: voter })
)

(define-read-only (is-member (address principal))
    (default-to false (map-get? Members address))
)

(define-read-only (get-current-proposal)
    (map-get? Proposals (var-get current-proposal-id))
)
