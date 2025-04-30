;; ecoweave.clar

;; =======================================
;; EcoWeave Community Cleanup Network
;; =======================================
;; This contract manages the full lifecycle of community clean-up events - from creation 
;; to completion, tracks participation, manages resources, and distributes reputation tokens
;; to participants as proof of their environmental stewardship.

;; =======================================
;; Error Constants
;; =======================================
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-EVENT-NOT-FOUND (err u101))
(define-constant ERR-USER-NOT-FOUND (err u102))
(define-constant ERR-EVENT-ALREADY-EXISTS (err u103))
(define-constant ERR-EVENT-ALREADY-COMPLETED (err u104))
(define-constant ERR-EVENT-NOT-COMPLETED (err u105))
(define-constant ERR-ALREADY-REGISTERED (err u106))
(define-constant ERR-INSUFFICIENT-FUNDS (err u107))
(define-constant ERR-EVENT-NOT-ACTIVE (err u108))
(define-constant ERR-INVALID-INPUT (err u109))
(define-constant ERR-MAX-PARTICIPANTS-REACHED (err u110))

;; =======================================
;; Data Maps and Variables
;; =======================================

;; A map to store user profiles with reputation and participation history
(define-map users 
  { user: principal }
  {
    reputation: uint,                ;; Combined reputation score
    events-organized: uint,          ;; Count of events organized
    events-participated: uint,       ;; Count of events participated in
    total-contributions: uint        ;; Total STX contributed to events
  }
)

;; Core data structure for cleanup events
(define-map cleanup-events
  { event-id: uint }
  {
    organizer: principal,            ;; Event creator
    name: (string-ascii 100),        ;; Event name
    description: (string-utf8 500),  ;; Detailed description
    location: (string-ascii 100),    ;; Physical location
    date: uint,                      ;; Unix timestamp for the event
    status: (string-ascii 20),       ;; "planned", "active", "completed", "cancelled"
    max-participants: uint,          ;; Maximum number of participants
    current-participants: uint,      ;; Current count of registered participants
    resources-needed: uint,          ;; Funding target in microSTX
    resources-collected: uint,       ;; Current funding in microSTX
    verification-data: (optional (string-ascii 200))  ;; IPFS hash to verification data
  }
)

;; Tracks participation in specific events
(define-map event-participants
  { event-id: uint, participant: principal }
  {
    registered: bool,                ;; Whether user registered for event
    contributed-amount: uint,        ;; Amount of STX contributed
    participated: bool,              ;; Whether user actually participated (verified)
    reputation-awarded: uint         ;; Reputation tokens awarded for this event
  }
)

;; Contract data variables
(define-data-var next-event-id uint u1)  ;; Auto-incrementing event ID

;; =======================================
;; Private Functions
;; =======================================

;; Initialize or get a user profile
(define-private (get-or-create-user (user principal))
  (match (map-get? users { user: user })
    existing-user existing-user
    {
      reputation: u0,
      events-organized: u0,
      events-participated: u0,
      total-contributions: u0
    }
  )
)

;; Update a user's profile after participation or contribution
(define-private (update-user-profile
  (user principal)
  (add-reputation uint)
  (organized bool)
  (participated bool)
  (contribution uint)
)
  (let (
    (current-profile (get-or-create-user user))
    (new-reputation (+ (get reputation current-profile) add-reputation))
    (new-organized (if organized (+ (get events-organized current-profile) u1) (get events-organized current-profile)))
    (new-participated (if participated (+ (get events-participated current-profile) u1) (get events-participated current-profile)))
    (new-contributions (+ (get total-contributions current-profile) contribution))
  )
    (map-set users
      { user: user }
      {
        reputation: new-reputation,
        events-organized: new-organized,
        events-participated: new-participated,
        total-contributions: new-contributions
      }
    )
  )
)

;; Checks if event exists and returns it
(define-private (get-event (event-id uint))
  (match (map-get? cleanup-events { event-id: event-id })
    event event
    (begin
      (print { error: "Event not found", event-id: event-id })
      none
    )
  )
)

;; =======================================
;; Read-Only Functions
;; =======================================

;; Get details of a specific cleanup event
(define-read-only (get-event-details (event-id uint))
  (match (map-get? cleanup-events { event-id: event-id })
    event (ok event)
    ERR-EVENT-NOT-FOUND
  )
)

;; Get user profile and reputation information
(define-read-only (get-user-profile (user principal))
  (match (map-get? users { user: user })
    profile (ok profile)
    ERR-USER-NOT-FOUND
  )
)

;; Check if a user is registered for an event
(define-read-only (is-participant (event-id uint) (user principal))
  (match (map-get? event-participants { event-id: event-id, participant: user })
    participant (ok (get registered participant))
    (ok false)
  )
)

;; Get the number of available spots in an event
(define-read-only (get-available-spots (event-id uint))
  (match (map-get? cleanup-events { event-id: event-id })
    event (ok (- (get max-participants event) (get current-participants event)))
    ERR-EVENT-NOT-FOUND
  )
)

;; Get the funding status of an event
(define-read-only (get-funding-status (event-id uint))
  (match (map-get? cleanup-events { event-id: event-id })
    event (ok {
      target: (get resources-needed event),
      collected: (get resources-collected event),
      percentage: (if (> (get resources-needed event) u0)
                     (/ (* (get resources-collected event) u100) (get resources-needed event))
                     u0)
    })
    ERR-EVENT-NOT-FOUND
  )
)

;; =======================================
;; Public Functions
;; =======================================

;; Create a new cleanup event
(define-public (create-event 
  (name (string-ascii 100))
  (description (string-utf8 500))
  (location (string-ascii 100))
  (date uint)
  (max-participants uint)
  (resources-needed uint)
)
  (let (
    (event-id (var-get next-event-id))
    (organizer tx-sender)
  )
    ;; Input validation
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len description) u0) ERR-INVALID-INPUT)
    (asserts! (> (len location) u0) ERR-INVALID-INPUT)
    (asserts! (> date (unwrap-panic (get-block-info? time u0))) ERR-INVALID-INPUT)
    (asserts! (> max-participants u0) ERR-INVALID-INPUT)

    ;; Create the event
    (map-set cleanup-events
      { event-id: event-id }
      {
        organizer: organizer,
        name: name,
        description: description,
        location: location,
        date: date,
        status: "planned",
        max-participants: max-participants,
        current-participants: u0,
        resources-needed: resources-needed,
        resources-collected: u0,
        verification-data: none
      }
    )

    ;; Update organizer's profile
    (update-user-profile organizer u10 true false u0)
    
    ;; Increment the event ID counter
    (var-set next-event-id (+ event-id u1))
    
    (ok event-id)
  )
)

;; Register to participate in a cleanup event
(define-public (register-for-event (event-id uint))
  (let (
    (user tx-sender)
  )
    (match (map-get? cleanup-events { event-id: event-id })
      event
      (begin
        ;; Check if event is still accepting participants
        (asserts! (or (is-eq (get status event) "planned") (is-eq (get status event) "active")) ERR-EVENT-NOT-ACTIVE)
        (asserts! (< (get current-participants event) (get max-participants event)) ERR-MAX-PARTICIPANTS-REACHED)
        
        ;; Check if user is already registered
        (asserts! (not (default-to false 
                        (match (map-get? event-participants { event-id: event-id, participant: user })
                          participant (get registered participant)
                          false))) 
                  ERR-ALREADY-REGISTERED)
        
        ;; Register the user
        (map-set event-participants
          { event-id: event-id, participant: user }
          {
            registered: true,
            contributed-amount: u0,
            participated: false,
            reputation-awarded: u0
          }
        )
        
        ;; Update event participation count
        (map-set cleanup-events
          { event-id: event-id }
          (merge event { current-participants: (+ (get current-participants event) u1) })
        )
        
        (ok true)
      )
      ERR-EVENT-NOT-FOUND
    )
  )
)

;; Contribute resources (STX) to a cleanup event
(define-public (contribute-to-event (event-id uint) (amount uint))
  (let (
    (user tx-sender)
  )
    (match (map-get? cleanup-events { event-id: event-id })
      event
      (begin
        ;; Check if event is still accepting contributions
        (asserts! (or (is-eq (get status event) "planned") (is-eq (get status event) "active")) ERR-EVENT-NOT-ACTIVE)
        
        ;; Transfer STX from contributor to contract
        (try! (stx-transfer? amount user (as-contract tx-sender)))
        
        ;; Update event funding
        (map-set cleanup-events
          { event-id: event-id }
          (merge event { resources-collected: (+ (get resources-collected event) amount) })
        )
        
        ;; Update participant record
        (match (map-get? event-participants { event-id: event-id, participant: user })
          participant
          (map-set event-participants
            { event-id: event-id, participant: user }
            (merge participant { contributed-amount: (+ (get contributed-amount participant) amount) })
          )
          ;; Create new participant record if not registered yet
          (map-set event-participants
            { event-id: event-id, participant: user }
            {
              registered: false,
              contributed-amount: amount,
              participated: false,
              reputation-awarded: u0
            }
          )
        )
        
        ;; Update user profile with contribution
        (update-user-profile user u5 false false amount)
        
        (ok true)
      )
      ERR-EVENT-NOT-FOUND
    )
  )
)

;; Activate an event - transition from planned to active
(define-public (activate-event (event-id uint))
  (let (
    (user tx-sender)
  )
    (match (map-get? cleanup-events { event-id: event-id })
      event
      (begin
        ;; Only organizer can activate
        (asserts! (is-eq user (get organizer event)) ERR-NOT-AUTHORIZED)
        ;; Check event is in planned state
        (asserts! (is-eq (get status event) "planned") ERR-INVALID-INPUT)
        
        ;; Update event status
        (map-set cleanup-events
          { event-id: event-id }
          (merge event { status: "active" })
        )
        
        (ok true)
      )
      ERR-EVENT-NOT-FOUND
    )
  )
)

;; Mark an event as completed and submit verification data
(define-public (complete-event (event-id uint) (verification-data (string-ascii 200)))
  (let (
    (user tx-sender)
  )
    (match (map-get? cleanup-events { event-id: event-id })
      event
      (begin
        ;; Only organizer can complete an event
        (asserts! (is-eq user (get organizer event)) ERR-NOT-AUTHORIZED)
        ;; Check event is in active state
        (asserts! (is-eq (get status event) "active") ERR-EVENT-NOT-ACTIVE)
        ;; Verification data must be provided
        (asserts! (> (len verification-data) u0) ERR-INVALID-INPUT)
        
        ;; Update event status and add verification data
        (map-set cleanup-events
          { event-id: event-id }
          (merge event { 
            status: "completed",
            verification-data: (some verification-data)
          })
        )
        
        ;; Award additional reputation to organizer for completing the event
        (update-user-profile user u15 false false u0)
        
        (ok true)
      )
      ERR-EVENT-NOT-FOUND
    )
  )
)

;; Confirm participation for a user (called by organizer)
(define-public (confirm-participation (event-id uint) (participant principal))
  (let (
    (user tx-sender)
  )
    (match (map-get? cleanup-events { event-id: event-id })
      event
      (begin
        ;; Only organizer can confirm participation
        (asserts! (is-eq user (get organizer event)) ERR-NOT-AUTHORIZED)
        ;; Event must be completed
        (asserts! (is-eq (get status event) "completed") ERR-EVENT-NOT-COMPLETED)
        
        (match (map-get? event-participants { event-id: event-id, participant: participant })
          participant-record
          (begin
            ;; Check if the user was registered
            (asserts! (get registered participant-record) ERR-USER-NOT-FOUND)
            
            ;; Set participation to true and award reputation
            (map-set event-participants
              { event-id: event-id, participant: participant }
              (merge participant-record { 
                participated: true,
                reputation-awarded: u20
              })
            )
            
            ;; Update the user's profile with earned reputation
            (update-user-profile participant u20 false true u0)
            
            (ok true)
          )
          ERR-USER-NOT-FOUND
        )
      )
      ERR-EVENT-NOT-FOUND
    )
  )
)

;; Cancel an event and return contributions
(define-public (cancel-event (event-id uint))
  (let (
    (user tx-sender)
  )
    (match (map-get? cleanup-events { event-id: event-id })
      event
      (begin
        ;; Only organizer can cancel
        (asserts! (is-eq user (get organizer event)) ERR-NOT-AUTHORIZED)
        ;; Event must not be already completed
        (asserts! (not (is-eq (get status event) "completed")) ERR-EVENT-ALREADY-COMPLETED)
        
        ;; Update event status
        (map-set cleanup-events
          { event-id: event-id }
          (merge event { status: "cancelled" })
        )
        
        ;; Note: In a production contract, you would implement logic here to
        ;; return all contributed STX to the original contributors
        
        (ok true)
      )
      ERR-EVENT-NOT-FOUND
    )
  )
)

;; Withdraw resources for an event (can only be called by organizer)
(define-public (withdraw-resources (event-id uint) (amount uint))
  (let (
    (user tx-sender)
  )
    (match (map-get? cleanup-events { event-id: event-id })
      event
      (begin
        ;; Only organizer can withdraw
        (asserts! (is-eq user (get organizer event)) ERR-NOT-AUTHORIZED)
        ;; Event must be active or completed
        (asserts! (or (is-eq (get status event) "active") (is-eq (get status event) "completed")) ERR-EVENT-NOT-ACTIVE)
        ;; Can't withdraw more than available
        (asserts! (<= amount (get resources-collected event)) ERR-INSUFFICIENT-FUNDS)
        
        ;; Transfer STX to organizer
        (try! (as-contract (stx-transfer? amount tx-sender user)))
        
        ;; Update event resources
        (map-set cleanup-events
          { event-id: event-id }
          (merge event { resources-collected: (- (get resources-collected event) amount) })
        )
        
        (ok true)
      )
      ERR-EVENT-NOT-FOUND
    )
  )
)