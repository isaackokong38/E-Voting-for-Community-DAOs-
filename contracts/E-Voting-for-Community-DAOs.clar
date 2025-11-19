(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-VOTE-CLOSED (err u101))
(define-constant ERR-ALREADY-VOTED (err u102))
(define-constant ERR-INVALID-VOTE (err u103))
(define-constant ERR-NO-ACTIVE-PROPOSAL (err u104))
(define-constant ERR-PROPOSAL-EXISTS (err u105))
(define-constant ERR-PROPOSAL-FINALIZED (err u106))
(define-constant ERR-PROPOSAL-NOT-ENDED (err u107))
(define-data-var admin principal tx-sender)
(define-data-var current-proposal-id uint u0)
(define-data-var total-proposals uint u0)
(define-data-var quorum-percentage uint u20)
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

(define-public (set-quorum-percentage (percentage uint))
    (begin
        (asserts! (is-eq tx-sender (var-get admin)) ERR-NOT-AUTHORIZED)
        (asserts! (and (> percentage u0) (<= percentage u100)) ERR-INVALID-VOTE)
        (var-set quorum-percentage percentage)
        (ok percentage)
    )
)

(define-public (finalize-proposal (proposal-id uint))
    (let
        (
            (proposal (unwrap! (map-get? Proposals proposal-id) ERR-NO-ACTIVE-PROPOSAL))
            (current-status (get status proposal))
            (active-members (var-get total-active-members))
            (total-votes (+ (get yes-votes proposal) (get no-votes proposal)))
            (required-quorum (var-get quorum-percentage))
        )
        (asserts! (is-some (map-get? Members tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq current-status "active") ERR-PROPOSAL-FINALIZED)
        (asserts! (>= stacks-block-height (get end-block proposal)) ERR-PROPOSAL-NOT-ENDED)
        (let
            (
                (quorum-met (if (and (> active-members u0) (> total-votes u0))
                                (>= (* total-votes u100) (* active-members required-quorum))
                                false))
                (new-status (if quorum-met
                                (if (> (get yes-votes proposal) (get no-votes proposal))
                                    "passed"
                                    (if (> (get no-votes proposal) (get yes-votes proposal))
                                        "rejected"
                                        "tie"))
                                "quorum-failed"))
            )
            (map-set Proposals proposal-id (merge proposal { status: new-status }))
            (ok { quorum-met: quorum-met, status: new-status })
        )
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

;; =============================================================================
;; VOTING ANALYTICS SYSTEM
;; =============================================================================

;; Analytics Constants
(define-constant ANALYTICS-ERR-NOT-FOUND (err u200))
(define-constant ANALYTICS-ERR-INVALID-PERIOD (err u201))
(define-constant MAX-RESPONSE-TIME u1000)
(define-constant ENGAGEMENT-HIGH-THRESHOLD u50)
(define-constant ENGAGEMENT-MEDIUM-THRESHOLD u20)

;; Analytics Data Variables
(define-data-var total-votes-platform uint u0)
(define-data-var total-active-members uint u0)
(define-data-var analytics-enabled bool true)
(define-data-var analytics-block-window uint u144) ;; ~24 hours in blocks

;; Voting Patterns Tracking
(define-map VotingPatterns
    principal
    {
        total-votes: uint,
        yes-votes: uint,
        no-votes: uint,
        consecutive-participations: uint,
        last-vote-block: uint,
        average-response-time: uint,
        participation-streak: uint
    }
)

;; Proposal Analytics
(define-map ProposalAnalytics
    uint
    {
        participation-rate: uint,
        engagement-score: uint,
        first-vote-block: uint,
        last-vote-block: uint,
        peak-voting-hour: uint,
        voting-momentum: uint
    }
)

;; Member Engagement Metrics
(define-map MemberEngagementMetrics
    principal
    {
        engagement-level: (string-ascii 20),
        participation-frequency: uint,
        consistency-score: uint,
        influence-rating: uint,
        activity-score: uint
    }
)

;; Time-Based Statistics
(define-map PlatformStatistics
    uint ;; time-period identifier
    {
        proposals-in-period: uint,
        votes-in-period: uint,
        unique-voters: uint,
        average-participation: uint,
        most-active-member: (optional principal)
    }
)

;; Proposal Trend Analysis
(define-map ProposalTrends
    uint ;; proposal-id
    {
        voting-velocity: uint,
        sentiment-trend: (string-ascii 20),
        participation-pattern: (string-ascii 30),
        completion-rate: uint
    }
)

;; =============================================================================
;; ANALYTICS HELPER FUNCTIONS
;; =============================================================================

(define-private (min-uint (a uint) (b uint))
    (if (< a b) a b)
)

(define-private (max-uint (a uint) (b uint))
    (if (> a b) a b)
)

(define-private (abs-uint (a uint))
    a ;; Since uint is always positive in Clarity
)

(define-private (calculate-response-time (proposal-start-block uint) (vote-block uint))
    (if (> vote-block proposal-start-block)
        (min-uint (- vote-block proposal-start-block) MAX-RESPONSE-TIME)
        u1)
)

(define-private (calculate-engagement-level (total-votes uint) (participation-rate uint))
    (if (and (>= total-votes ENGAGEMENT-HIGH-THRESHOLD) (>= participation-rate u80))
        "highly-engaged"
        (if (and (>= total-votes ENGAGEMENT-MEDIUM-THRESHOLD) (>= participation-rate u50))
            "moderately-engaged"
            "low-engagement"))
)

(define-private (update-member-analytics (member principal) (vote-bool bool) (proposal-id uint))
    (let
        (
            (proposal (unwrap! (map-get? Proposals proposal-id) false))
            (current-patterns (default-to 
                { total-votes: u0, yes-votes: u0, no-votes: u0, consecutive-participations: u0, 
                  last-vote-block: u0, average-response-time: u0, participation-streak: u0 }
                (map-get? VotingPatterns member)))
            (response-time (calculate-response-time (get start-block proposal) stacks-block-height))
            (new-total (+ (get total-votes current-patterns) u1))
            (new-yes (if vote-bool (+ (get yes-votes current-patterns) u1) (get yes-votes current-patterns)))
            (new-no (if vote-bool (get no-votes current-patterns) (+ (get no-votes current-patterns) u1)))
            (streak-bonus (if (and (> (get last-vote-block current-patterns) u0)
                                 (<= (- stacks-block-height (get last-vote-block current-patterns)) u50))
                            (+ (get participation-streak current-patterns) u1)
                            u1))
            (new-avg-response (if (> new-total u0)
                               (/ (+ (* (get average-response-time current-patterns) (get total-votes current-patterns)) 
                                    response-time) new-total)
                               response-time))
        )
        ;; Update voting patterns
        (map-set VotingPatterns member {
            total-votes: new-total,
            yes-votes: new-yes,
            no-votes: new-no,
            consecutive-participations: (+ (get consecutive-participations current-patterns) u1),
            last-vote-block: stacks-block-height,
            average-response-time: new-avg-response,
            participation-streak: streak-bonus
        })
        
        ;; Update engagement metrics
        (let
            (
                (participation-rate (if (> (var-get total-proposals) u0)
                                     (/ (* new-total u100) (var-get total-proposals))
                                     u0))
                (consistency-score (if (> new-total u0)
                                    (/ (* (min-uint new-yes new-no) u100) new-total)
                                    u50))
                (influence-rating (+ new-total streak-bonus))
                (activity-score (+ (* new-total u2) streak-bonus))
            )
            (map-set MemberEngagementMetrics member {
                engagement-level: (calculate-engagement-level new-total participation-rate),
                participation-frequency: new-total,
                consistency-score: consistency-score,
                influence-rating: influence-rating,
                activity-score: activity-score
            })
        )
        
        ;; Update platform statistics
        (var-set total-votes-platform (+ (var-get total-votes-platform) u1))
        true
    )
)

(define-private (update-proposal-analytics (proposal-id uint))
    (let
        (
            (proposal (unwrap! (map-get? Proposals proposal-id) false))
            (current-analytics (default-to 
                { participation-rate: u0, engagement-score: u0, first-vote-block: u0, 
                  last-vote-block: u0, peak-voting-hour: u0, voting-momentum: u0 }
                (map-get? ProposalAnalytics proposal-id)))
            (total-votes (+ (get yes-votes proposal) (get no-votes proposal)))
            (first-vote (if (is-eq (get first-vote-block current-analytics) u0) 
                           stacks-block-height 
                           (get first-vote-block current-analytics)))
            (momentum (if (> total-votes u0)
                        (/ total-votes (max-uint (- stacks-block-height (get start-block proposal)) u1))
                        u0))
        )
        (map-set ProposalAnalytics proposal-id {
            participation-rate: (if (> (var-get total-active-members) u0)
                                 (/ (* total-votes u100) (var-get total-active-members))
                                 u0),
            engagement-score: (+ total-votes momentum),
            first-vote-block: first-vote,
            last-vote-block: stacks-block-height,
            peak-voting-hour: (mod stacks-block-height u24),
            voting-momentum: momentum
        })
        
        ;; Update proposal trends
        (let
            (
                (yes-votes (get yes-votes proposal))
                (no-votes (get no-votes proposal))
                (sentiment (if (> yes-votes no-votes) "positive" 
                             (if (> no-votes yes-votes) "negative" "neutral")))
                (pattern (if (> momentum u5) "high-activity" 
                           (if (> momentum u2) "moderate-activity" "low-activity")))
            )
            (map-set ProposalTrends proposal-id {
                voting-velocity: momentum,
                sentiment-trend: sentiment,
                participation-pattern: pattern,
                completion-rate: (if (> (var-get total-active-members) u0)
                                  (/ (* total-votes u100) (var-get total-active-members))
                                  u0)
            })
        )
        true
    )
)

;; Enhanced voting function with analytics
(define-public (vote-with-analytics (proposal-id uint) (vote-bool bool))
    (let
        (
            (proposal (unwrap! (map-get? Proposals proposal-id) ERR-NO-ACTIVE-PROPOSAL))
            (voter-key { proposal-id: proposal-id, voter: tx-sender })
        )
        (asserts! (is-some (map-get? Members tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (not (is-some (map-get? Voters voter-key))) ERR-ALREADY-VOTED)
        (asserts! (< stacks-block-height (get end-block proposal)) ERR-VOTE-CLOSED)
        (asserts! (var-get analytics-enabled) ERR-NOT-AUTHORIZED)
        
        ;; Record the vote
        (map-set Voters voter-key { vote: vote-bool })
        
        ;; Update vote counts
        (if vote-bool
            (map-set Proposals proposal-id (merge proposal { yes-votes: (+ (get yes-votes proposal) u1) }))
            (map-set Proposals proposal-id (merge proposal { no-votes: (+ (get no-votes proposal) u1) }))
        )
        
        ;; Update analytics if enabled
        (if (var-get analytics-enabled)
            (begin
                (update-member-analytics tx-sender vote-bool proposal-id)
                (update-proposal-analytics proposal-id)
            )
            true
        )
        
        (ok true)
    )
)

;; =============================================================================
;; ANALYTICS READ-ONLY FUNCTIONS
;; =============================================================================

(define-read-only (get-member-voting-patterns (member principal))
    (map-get? VotingPatterns member)
)

(define-read-only (get-member-engagement-metrics (member principal))
    (map-get? MemberEngagementMetrics member)
)

(define-read-only (get-proposal-analytics (proposal-id uint))
    (map-get? ProposalAnalytics proposal-id)
)

(define-read-only (get-proposal-trends (proposal-id uint))
    (map-get? ProposalTrends proposal-id)
)

(define-read-only (get-platform-overview)
    (ok {
        total-votes: (var-get total-votes-platform),
        total-proposals: (var-get total-proposals),
        active-members: (var-get total-active-members),
        analytics-enabled: (var-get analytics-enabled),
        current-block: stacks-block-height
    })
)

(define-read-only (calculate-member-influence-score (member principal))
    (let
        (
            (patterns (default-to 
                { total-votes: u0, yes-votes: u0, no-votes: u0, consecutive-participations: u0, 
                  last-vote-block: u0, average-response-time: u0, participation-streak: u0 }
                (map-get? VotingPatterns member)))
            (engagement (default-to 
                { engagement-level: "low-engagement", participation-frequency: u0, 
                  consistency-score: u0, influence-rating: u0, activity-score: u0 }
                (map-get? MemberEngagementMetrics member)))
            (base-score (get total-votes patterns))
            (streak-bonus (* (get participation-streak patterns) u2))
            (consistency-bonus (/ (get consistency-score engagement) u10))
            (activity-bonus (/ (get activity-score engagement) u5))
        )
        (ok (+ base-score streak-bonus consistency-bonus activity-bonus))
    )
)

(define-read-only (get-voting-behavior-analysis (member principal))
    (let
        (
            (patterns (default-to 
                { total-votes: u0, yes-votes: u0, no-votes: u0, consecutive-participations: u0, 
                  last-vote-block: u0, average-response-time: u0, participation-streak: u0 }
                (map-get? VotingPatterns member)))
            (total-votes (get total-votes patterns))
            (yes-ratio (if (> total-votes u0) 
                         (/ (* (get yes-votes patterns) u100) total-votes) 
                         u50))
            (response-speed (if (< (get average-response-time patterns) u10) 
                             "very-fast" 
                             (if (< (get average-response-time patterns) u50) 
                                "fast" 
                                "moderate")))
        )
        (ok {
            yes-vote-tendency: yes-ratio,
            response-speed: response-speed,
            participation-consistency: (get participation-streak patterns),
            total-participations: total-votes,
            last-activity: (get last-vote-block patterns)
        })
    )
)

(define-read-only (get-proposal-performance-metrics (proposal-id uint))
    (let
        (
            (proposal (unwrap! (map-get? Proposals proposal-id) ANALYTICS-ERR-NOT-FOUND))
            (analytics (default-to 
                { participation-rate: u0, engagement-score: u0, first-vote-block: u0, 
                  last-vote-block: u0, peak-voting-hour: u0, voting-momentum: u0 }
                (map-get? ProposalAnalytics proposal-id)))
            (trends (default-to 
                { voting-velocity: u0, sentiment-trend: "neutral", 
                  participation-pattern: "low-activity", completion-rate: u0 }
                (map-get? ProposalTrends proposal-id)))
            (total-votes (+ (get yes-votes proposal) (get no-votes proposal)))
            (time-active (- stacks-block-height (get start-block proposal)))
        )
        (ok {
            total-votes: total-votes,
            participation-rate: (get participation-rate analytics),
            voting-momentum: (get voting-momentum analytics),
            sentiment: (get sentiment-trend trends),
            time-to-first-vote: (if (> (get first-vote-block analytics) u0)
                                  (- (get first-vote-block analytics) (get start-block proposal))
                                  u0),
            activity-pattern: (get participation-pattern trends),
            engagement-score: (get engagement-score analytics)
        })
    )
)

(define-read-only (get-top-engaged-members-count)
    (ok (var-get total-active-members))
)

;; Admin functions for analytics management
(define-public (toggle-analytics)
    (begin
        (asserts! (is-eq tx-sender (var-get admin)) ERR-NOT-AUTHORIZED)
        (var-set analytics-enabled (not (var-get analytics-enabled)))
        (ok (var-get analytics-enabled))
    )
)

(define-public (initialize-member-analytics (member principal))
    (begin
        (asserts! (is-eq tx-sender (var-get admin)) ERR-NOT-AUTHORIZED)
        (asserts! (is-some (map-get? Members member)) ERR-NOT-AUTHORIZED)
        (var-set total-active-members (+ (var-get total-active-members) u1))
        (ok true)
    )
)
