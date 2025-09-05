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
        (update-member-reputation-proposal tx-sender)
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

(define-map Delegations
    principal
    principal
)

(define-map DelegatedVotePower
    { proposal-id: uint, delegate: principal }
    uint
)

(define-public (delegate-vote (delegate-to principal))
    (begin
        (asserts! (is-some (map-get? Members tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (is-some (map-get? Members delegate-to)) ERR-NOT-AUTHORIZED)
        (asserts! (not (is-eq tx-sender delegate-to)) ERR-INVALID-VOTE)
        (ok (map-set Delegations tx-sender delegate-to))
    )
)

(define-public (revoke-delegation)
    (begin
        (asserts! (is-some (map-get? Members tx-sender)) ERR-NOT-AUTHORIZED)
        (ok (map-delete Delegations tx-sender))
    )
)

(define-public (vote-with-delegation (proposal-id uint) (vote-bool bool))
    (let
        (
            (proposal (unwrap! (map-get? Proposals proposal-id) ERR-NO-ACTIVE-PROPOSAL))
            (voter-key { proposal-id: proposal-id, voter: tx-sender })
            (delegate-key { proposal-id: proposal-id, delegate: tx-sender })
            (delegated-power (default-to u0 (map-get? DelegatedVotePower delegate-key)))
            (total-votes (+ u1 delegated-power))
        )
        (asserts! (is-some (map-get? Members tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (not (is-some (map-get? Voters voter-key))) ERR-ALREADY-VOTED)
        (asserts! (< stacks-block-height (get end-block proposal)) ERR-VOTE-CLOSED)
        (map-set Voters voter-key { vote: vote-bool })
        (if vote-bool
            (map-set Proposals proposal-id (merge proposal { yes-votes: (+ (get yes-votes proposal) total-votes) }))
            (map-set Proposals proposal-id (merge proposal { no-votes: (+ (get no-votes proposal) total-votes) }))
        )
        (map-delete DelegatedVotePower delegate-key)
        (ok true)
    )
)

(define-private (update-delegation-power (proposal-id uint) (delegator principal) (delegate principal))
    (let
        (
            (delegate-key { proposal-id: proposal-id, delegate: delegate })
            (current-power (default-to u0 (map-get? DelegatedVotePower delegate-key)))
        )
        (map-set DelegatedVotePower delegate-key (+ current-power u1))
    )
)

(define-read-only (get-delegation (delegator principal))
    (map-get? Delegations delegator)
)

(define-read-only (get-delegated-power (proposal-id uint) (delegate principal))
    (default-to u0 (map-get? DelegatedVotePower { proposal-id: proposal-id, delegate: delegate }))
)

(define-constant CATEGORY-GOVERNANCE "governance")
(define-constant CATEGORY-TREASURY "treasury")
(define-constant CATEGORY-TECHNICAL "technical")
(define-constant CATEGORY-GENERAL "general")

(define-map CategoryConfig
    (string-ascii 20)
    {
        min-voting-period: uint,
        max-voting-period: uint,
        required-quorum: uint
    }
)

(define-map ProposalsByCategory
    { category: (string-ascii 20), proposal-id: uint }
    bool
)

(define-data-var category-count uint u0)

(define-public (setup-category (category (string-ascii 20)) (min-period uint) (max-period uint) (quorum uint))
    (begin
        (asserts! (is-eq tx-sender (var-get admin)) ERR-NOT-AUTHORIZED)
        (asserts! (< min-period max-period) ERR-INVALID-VOTE)
        (asserts! (> quorum u0) ERR-INVALID-VOTE)
        (ok (map-set CategoryConfig category {
            min-voting-period: min-period,
            max-voting-period: max-period,
            required-quorum: quorum
        }))
    )
)

(define-public (create-categorized-proposal 
    (title (string-ascii 100)) 
    (description (string-ascii 500)) 
    (blocks uint) 
    (category (string-ascii 20)))
    (let
        (
            (proposal-id (+ (var-get total-proposals) u1))
            (start-block stacks-block-height)
            (end-block (+ stacks-block-height blocks))
            (category-config (unwrap! (map-get? CategoryConfig category) ERR-INVALID-VOTE))
        )
        (asserts! (is-some (map-get? Members tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (>= blocks (get min-voting-period category-config)) ERR-INVALID-VOTE)
        (asserts! (<= blocks (get max-voting-period category-config)) ERR-INVALID-VOTE)
        (var-set total-proposals proposal-id)
        (var-set current-proposal-id proposal-id)
        (update-member-reputation-proposal tx-sender)
        (map-set ProposalsByCategory { category: category, proposal-id: proposal-id } true)
        (ok (map-set Proposals proposal-id {
            title: title,
            description: description,
            creator: tx-sender,
            start-block: start-block,
            end-block: end-block,
            yes-votes: u0,
            no-votes: u0,
            status: category
        }))
    )
)

(define-read-only (get-category-config (category (string-ascii 20)))
    (map-get? CategoryConfig category)
)

(define-read-only (is-proposal-in-category (category (string-ascii 20)) (proposal-id uint))
    (default-to false (map-get? ProposalsByCategory { category: category, proposal-id: proposal-id }))
)

(define-read-only (check-quorum-met (proposal-id uint))
    (let
        (
            (proposal (unwrap! (map-get? Proposals proposal-id) (err u404)))
            (category-config (unwrap! (map-get? CategoryConfig (get status proposal)) (err u404)))
            (total-votes (+ (get yes-votes proposal) (get no-votes proposal)))
        )
        (ok (>= total-votes (get required-quorum category-config)))
    )
)

(define-public (finalize-proposal (proposal-id uint))
    (let
        (
            (proposal (unwrap! (map-get? Proposals proposal-id) ERR-NO-ACTIVE-PROPOSAL))
            (current-status (get status proposal))
            (voting-ended (>= stacks-block-height (get end-block proposal)))
            (total-votes (+ (get yes-votes proposal) (get no-votes proposal)))
            (yes-votes (get yes-votes proposal))
            (no-votes (get no-votes proposal))
        )
        (asserts! voting-ended ERR-VOTE-CLOSED)
        (asserts! (or (is-eq current-status "active") 
                     (is-eq current-status CATEGORY-GOVERNANCE)
                     (is-eq current-status CATEGORY-TREASURY)
                     (is-eq current-status CATEGORY-TECHNICAL)
                     (is-eq current-status CATEGORY-GENERAL)) ERR-INVALID-VOTE)
        (let
            (
                (quorum-met (if (or (is-eq current-status CATEGORY-GOVERNANCE)
                                   (is-eq current-status CATEGORY-TREASURY)
                                   (is-eq current-status CATEGORY-TECHNICAL)
                                   (is-eq current-status CATEGORY-GENERAL))
                               (let ((category-config (unwrap! (map-get? CategoryConfig current-status) ERR-INVALID-VOTE)))
                                    (>= total-votes (get required-quorum category-config)))
                               (> total-votes u0)))
                (final-status (if quorum-met
                                 (if (> yes-votes no-votes) "passed" "rejected")
                                 "failed"))
            )
            (ok (map-set Proposals proposal-id (merge proposal { status: final-status })))
        )
    )
)

(define-read-only (get-proposal-status (proposal-id uint))
    (let
        (
            (proposal (unwrap! (map-get? Proposals proposal-id) (err u404)))
            (voting-ended (>= stacks-block-height (get end-block proposal)))
            (current-status (get status proposal))
        )
        (if voting-ended
            (if (or (is-eq current-status "passed")
                   (is-eq current-status "rejected") 
                   (is-eq current-status "failed"))
                (ok current-status)
                (ok "expired"))
            (ok current-status))
    )
)

(define-read-only (is-proposal-active (proposal-id uint))
    (let
        (
            (proposal (unwrap! (map-get? Proposals proposal-id) (err u404)))
            (voting-ended (>= stacks-block-height (get end-block proposal)))
            (current-status (get status proposal))
        )
        (ok (and (not voting-ended)
                (or (is-eq current-status "active")
                   (is-eq current-status CATEGORY-GOVERNANCE)
                   (is-eq current-status CATEGORY-TREASURY)
                   (is-eq current-status CATEGORY-TECHNICAL)
                   (is-eq current-status CATEGORY-GENERAL))))
    )
)

(define-map MemberReputation
    principal
    {
        votes-cast: uint,
        proposals-created: uint,
        participation-score: uint,
        reputation-level: uint
    }
)

(define-constant REPUTATION-MULTIPLIER-BASE u1)
(define-constant REPUTATION-MULTIPLIER-BRONZE u2)
(define-constant REPUTATION-MULTIPLIER-SILVER u3)
(define-constant REPUTATION-MULTIPLIER-GOLD u5)

(define-constant BRONZE-THRESHOLD u10)
(define-constant SILVER-THRESHOLD u25)
(define-constant GOLD-THRESHOLD u50)

(define-private (calculate-reputation-level (score uint))
    (if (>= score GOLD-THRESHOLD)
        u4
        (if (>= score SILVER-THRESHOLD)
            u3
            (if (>= score BRONZE-THRESHOLD)
                u2
                u1)))
)

(define-private (get-reputation-multiplier (level uint))
    (if (is-eq level u4)
        REPUTATION-MULTIPLIER-GOLD
        (if (is-eq level u3)
            REPUTATION-MULTIPLIER-SILVER
            (if (is-eq level u2)
                REPUTATION-MULTIPLIER-BRONZE
                REPUTATION-MULTIPLIER-BASE)))
)

(define-private (update-member-reputation-vote (member principal))
    (let
        (
            (current-rep (default-to { votes-cast: u0, proposals-created: u0, participation-score: u0, reputation-level: u1 }
                                   (map-get? MemberReputation member)))
            (new-votes (+ (get votes-cast current-rep) u1))
            (new-score (+ (get participation-score current-rep) u1))
            (new-level (calculate-reputation-level new-score))
        )
        (map-set MemberReputation member {
            votes-cast: new-votes,
            proposals-created: (get proposals-created current-rep),
            participation-score: new-score,
            reputation-level: new-level
        })
    )
)

(define-private (update-member-reputation-proposal (member principal))
    (let
        (
            (current-rep (default-to { votes-cast: u0, proposals-created: u0, participation-score: u0, reputation-level: u1 }
                                   (map-get? MemberReputation member)))
            (new-proposals (+ (get proposals-created current-rep) u1))
            (new-score (+ (get participation-score current-rep) u2))
            (new-level (calculate-reputation-level new-score))
        )
        (map-set MemberReputation member {
            votes-cast: (get votes-cast current-rep),
            proposals-created: new-proposals,
            participation-score: new-score,
            reputation-level: new-level
        })
    )
)

(define-public (vote-with-reputation (proposal-id uint) (vote-bool bool))
    (let
        (
            (proposal (unwrap! (map-get? Proposals proposal-id) ERR-NO-ACTIVE-PROPOSAL))
            (voter-key { proposal-id: proposal-id, voter: tx-sender })
            (member-rep (default-to { votes-cast: u0, proposals-created: u0, participation-score: u0, reputation-level: u1 }
                                  (map-get? MemberReputation tx-sender)))
            (vote-weight (get-reputation-multiplier (get reputation-level member-rep)))
        )
        (asserts! (is-some (map-get? Members tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (not (is-some (map-get? Voters voter-key))) ERR-ALREADY-VOTED)
        (asserts! (< stacks-block-height (get end-block proposal)) ERR-VOTE-CLOSED)
        (map-set Voters voter-key { vote: vote-bool })
        (update-member-reputation-vote tx-sender)
        (if vote-bool
            (map-set Proposals proposal-id (merge proposal { yes-votes: (+ (get yes-votes proposal) vote-weight) }))
            (map-set Proposals proposal-id (merge proposal { no-votes: (+ (get no-votes proposal) vote-weight) }))
        )
        (ok true)
    )
)

(define-read-only (get-member-reputation (member principal))
    (map-get? MemberReputation member)
)

(define-read-only (get-voting-power (member principal))
    (let
        (
            (member-rep (default-to { votes-cast: u0, proposals-created: u0, participation-score: u0, reputation-level: u1 }
                                  (map-get? MemberReputation member)))
        )
        (get-reputation-multiplier (get reputation-level member-rep))
    )
)

(define-read-only (get-reputation-level-name (level uint))
    (if (is-eq level u4)
        "Gold"
        (if (is-eq level u3)
            "Silver"
            (if (is-eq level u2)
                "Bronze"
                "Base")))
)