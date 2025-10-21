;; title: On-Chain-Reservation-System

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-insufficient-funds (err u103))
(define-constant err-reservation-not-found (err u104))
(define-constant err-unauthorized (err u105))
(define-constant err-too-late-to-cancel (err u106))
(define-constant err-reservation-confirmed (err u107))
(define-constant err-invalid-time (err u108))
(define-constant err-restaurant-not-active (err u109))
(define-constant err-waitlist-not-found (err u110))
(define-constant err-already-on-waitlist (err u111))
(define-constant err-waitlist-full (err u112))
(define-constant err-not-on-waitlist (err u113))

(define-data-var next-restaurant-id uint u1)
(define-data-var next-reservation-id uint u1)
(define-data-var next-waitlist-id uint u1)

(define-map restaurants 
  { restaurant-id: uint }
  {
    owner: principal,
    name: (string-ascii 50),
    deposit-amount: uint,
    cancellation-window: uint,
    is-active: bool,
    total-reservations: uint,
    total-revenue: uint
  }
)

(define-map reservations
  { reservation-id: uint }
  {
    restaurant-id: uint,
    customer: principal,
    deposit-paid: uint,
    reservation-time: uint,
    created-at: uint,
    status: (string-ascii 20),
    party-size: uint
  }
)

(define-map restaurant-by-owner
  { owner: principal }
  { restaurant-id: uint }
)

(define-map customer-reservations
  { customer: principal, restaurant-id: uint }
  { reservation-ids: (list 50 uint) }
)

(define-map waitlist-entries
  { waitlist-id: uint }
  {
    restaurant-id: uint,
    customer: principal,
    desired-time: uint,
    party-size: uint,
    created-at: uint,
    status: (string-ascii 20),
    priority: uint
  }
)

(define-map restaurant-waitlist
  { restaurant-id: uint, desired-time: uint }
  { waitlist-ids: (list 100 uint) }
)

(define-map customer-waitlist
  { customer: principal }
  { waitlist-ids: (list 20 uint) }
)

(define-public (register-restaurant (name (string-ascii 50)) (deposit-amount uint) (cancellation-window uint))
  (let
    (
      (restaurant-id (var-get next-restaurant-id))
      (sender tx-sender)
    )
    (asserts! (> deposit-amount u0) err-insufficient-funds)
    (asserts! (> cancellation-window u0) err-invalid-time)
    (asserts! (is-none (map-get? restaurant-by-owner { owner: sender })) err-already-exists)
    
    (map-set restaurants
      { restaurant-id: restaurant-id }
      {
        owner: sender,
        name: name,
        deposit-amount: deposit-amount,
        cancellation-window: cancellation-window,
        is-active: true,
        total-reservations: u0,
        total-revenue: u0
      }
    )
    
    (map-set restaurant-by-owner
      { owner: sender }
      { restaurant-id: restaurant-id }
    )
    
    (var-set next-restaurant-id (+ restaurant-id u1))
    (ok restaurant-id)
  )
)

(define-public (make-reservation (restaurant-id uint) (reservation-time uint) (party-size uint))
  (let
    (
      (restaurant (unwrap! (map-get? restaurants { restaurant-id: restaurant-id }) err-not-found))
      (reservation-id (var-get next-reservation-id))
      (current-height stacks-block-height)
      (deposit-amount (get deposit-amount restaurant))
      (customer tx-sender)
    )
    (asserts! (get is-active restaurant) err-restaurant-not-active)
    (asserts! (> reservation-time current-height) err-invalid-time)
    (asserts! (> party-size u0) err-invalid-time)
    
    (try! (stx-transfer? deposit-amount customer (as-contract tx-sender)))
    
    (map-set reservations
      { reservation-id: reservation-id }
      {
        restaurant-id: restaurant-id,
        customer: customer,
        deposit-paid: deposit-amount,
        reservation-time: reservation-time,
        created-at: current-height,
        status: "pending",
        party-size: party-size
      }
    )
    
    (let
      (
        (existing-reservations (default-to (list) (get reservation-ids (map-get? customer-reservations { customer: customer, restaurant-id: restaurant-id }))))
        (updated-reservations (unwrap! (as-max-len? (append existing-reservations reservation-id) u50) err-insufficient-funds))
      )
      (map-set customer-reservations
        { customer: customer, restaurant-id: restaurant-id }
        { reservation-ids: updated-reservations }
      )
    )
    
    (map-set restaurants
      { restaurant-id: restaurant-id }
      (merge restaurant { total-reservations: (+ (get total-reservations restaurant) u1) })
    )
    
    (var-set next-reservation-id (+ reservation-id u1))
    (ok reservation-id)
  )
)

(define-public (cancel-reservation (reservation-id uint))
  (let
    (
      (reservation (unwrap! (map-get? reservations { reservation-id: reservation-id }) err-reservation-not-found))
      (restaurant (unwrap! (map-get? restaurants { restaurant-id: (get restaurant-id reservation) }) err-not-found))
      (current-height stacks-block-height)
      (cancellation-deadline (- (get reservation-time reservation) (get cancellation-window restaurant)))
      (customer (get customer reservation))
      (deposit-amount (get deposit-paid reservation))
    )
    (asserts! (is-eq tx-sender customer) err-unauthorized)
    (asserts! (is-eq (get status reservation) "pending") err-reservation-confirmed)
    (asserts! (<= current-height cancellation-deadline) err-too-late-to-cancel)
    
    (try! (as-contract (stx-transfer? deposit-amount tx-sender customer)))
    
    (map-set reservations
      { reservation-id: reservation-id }
      (merge reservation { status: "cancelled" })
    )
    
    (ok true)
  )
)

(define-public (reschedule-reservation (reservation-id uint) (new-reservation-time uint))
  (let
    (
      (reservation (unwrap! (map-get? reservations { reservation-id: reservation-id }) err-reservation-not-found))
      (restaurant (unwrap! (map-get? restaurants { restaurant-id: (get restaurant-id reservation) }) err-not-found))
      (customer (get customer reservation))
      (current-height stacks-block-height)
      (cancellation-deadline (- (get reservation-time reservation) (get cancellation-window restaurant)))
    )
    (asserts! (is-eq tx-sender customer) err-unauthorized)
    (asserts! (is-eq (get status reservation) "pending") err-reservation-confirmed)
    (asserts! (<= current-height cancellation-deadline) err-too-late-to-cancel)
    (asserts! (> new-reservation-time current-height) err-invalid-time)
    (map-set reservations
      { reservation-id: reservation-id }
      (merge reservation { reservation-time: new-reservation-time })
    )
    (ok true)
  )
)

(define-public (confirm-reservation (reservation-id uint))
  (let
    (
      (reservation (unwrap! (map-get? reservations { reservation-id: reservation-id }) err-reservation-not-found))
      (restaurant (unwrap! (map-get? restaurants { restaurant-id: (get restaurant-id reservation) }) err-not-found))
      (restaurant-owner (get owner restaurant))
      (deposit-amount (get deposit-paid reservation))
    )
    (asserts! (is-eq tx-sender restaurant-owner) err-unauthorized)
    (asserts! (is-eq (get status reservation) "pending") err-reservation-confirmed)
    
    (try! (as-contract (stx-transfer? deposit-amount tx-sender restaurant-owner)))
    
    (map-set reservations
      { reservation-id: reservation-id }
      (merge reservation { status: "confirmed" })
    )
    
    (map-set restaurants
      { restaurant-id: (get restaurant-id reservation) }
      (merge restaurant { total-revenue: (+ (get total-revenue restaurant) deposit-amount) })
    )
    
    (ok true)
  )
)

(define-public (handle-no-show (reservation-id uint))
  (let
    (
      (reservation (unwrap! (map-get? reservations { reservation-id: reservation-id }) err-reservation-not-found))
      (restaurant (unwrap! (map-get? restaurants { restaurant-id: (get restaurant-id reservation) }) err-not-found))
      (restaurant-owner (get owner restaurant))
      (current-height stacks-block-height)
      (deposit-amount (get deposit-paid reservation))
    )
    (asserts! (is-eq tx-sender restaurant-owner) err-unauthorized)
    (asserts! (is-eq (get status reservation) "pending") err-reservation-confirmed)
    (asserts! (> current-height (get reservation-time reservation)) err-invalid-time)
    
    (try! (as-contract (stx-transfer? deposit-amount tx-sender restaurant-owner)))
    
    (map-set reservations
      { reservation-id: reservation-id }
      (merge reservation { status: "no-show" })
    )
    
    (map-set restaurants
      { restaurant-id: (get restaurant-id reservation) }
      (merge restaurant { total-revenue: (+ (get total-revenue restaurant) deposit-amount) })
    )
    
    (ok true)
  )
)

(define-public (update-restaurant-settings (deposit-amount uint) (cancellation-window uint))
  (let
    (
      (restaurant-data (unwrap! (map-get? restaurant-by-owner { owner: tx-sender }) err-not-found))
      (restaurant-id (get restaurant-id restaurant-data))
      (restaurant (unwrap! (map-get? restaurants { restaurant-id: restaurant-id }) err-not-found))
    )
    (asserts! (> deposit-amount u0) err-insufficient-funds)
    (asserts! (> cancellation-window u0) err-invalid-time)
    
    (map-set restaurants
      { restaurant-id: restaurant-id }
      (merge restaurant { 
        deposit-amount: deposit-amount,
        cancellation-window: cancellation-window
      })
    )
    
    (ok true)
  )
)

(define-public (toggle-restaurant-status)
  (let
    (
      (restaurant-data (unwrap! (map-get? restaurant-by-owner { owner: tx-sender }) err-not-found))
      (restaurant-id (get restaurant-id restaurant-data))
      (restaurant (unwrap! (map-get? restaurants { restaurant-id: restaurant-id }) err-not-found))
    )
    (map-set restaurants
      { restaurant-id: restaurant-id }
      (merge restaurant { is-active: (not (get is-active restaurant)) })
    )
    
    (ok (not (get is-active restaurant)))
  )
)

(define-read-only (get-restaurant (restaurant-id uint))
  (map-get? restaurants { restaurant-id: restaurant-id })
)

(define-read-only (get-reservation (reservation-id uint))
  (map-get? reservations { reservation-id: reservation-id })
)

(define-read-only (get-restaurant-by-owner (owner principal))
  (match (map-get? restaurant-by-owner { owner: owner })
    restaurant-data (map-get? restaurants { restaurant-id: (get restaurant-id restaurant-data) })
    none
  )
)

(define-read-only (get-customer-reservations (customer principal) (restaurant-id uint))
  (map-get? customer-reservations { customer: customer, restaurant-id: restaurant-id })
)

(define-read-only (can-cancel-reservation (reservation-id uint))
  (match (map-get? reservations { reservation-id: reservation-id })
    reservation (match (map-get? restaurants { restaurant-id: (get restaurant-id reservation) })
      restaurant (let
        (
          (current-height stacks-block-height)
          (cancellation-deadline (- (get reservation-time reservation) (get cancellation-window restaurant)))
        )
        (and 
          (is-eq (get status reservation) "pending")
          (<= current-height cancellation-deadline)
        )
      )
      false
    )
    false
  )
)

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender))
)

(define-read-only (get-total-restaurants)
  (- (var-get next-restaurant-id) u1)
)

(define-read-only (get-total-reservations)
  (- (var-get next-reservation-id) u1)
)

(define-read-only (get-reservation-status (reservation-id uint))
  (match (map-get? reservations { reservation-id: reservation-id })
    reservation (some (get status reservation))
    none
  )
)

(define-read-only (calculate-refund (reservation-id uint))
  (match (map-get? reservations { reservation-id: reservation-id })
    reservation (if (can-cancel-reservation reservation-id)
      (some (get deposit-paid reservation))
      (some u0)
    )
    none
  )
)

(define-read-only (get-restaurant-stats (restaurant-id uint))
  (match (map-get? restaurants { restaurant-id: restaurant-id })
    restaurant (some {
      total-reservations: (get total-reservations restaurant),
      total-revenue: (get total-revenue restaurant),
      is-active: (get is-active restaurant)
    })
    none
  )
)

(define-public (join-waitlist (restaurant-id uint) (desired-time uint) (party-size uint))
  (let
    (
      (restaurant (unwrap! (map-get? restaurants { restaurant-id: restaurant-id }) err-not-found))
      (waitlist-id (var-get next-waitlist-id))
      (current-height stacks-block-height)
      (customer tx-sender)
      (existing-waitlist (default-to (list) (get waitlist-ids (map-get? restaurant-waitlist { restaurant-id: restaurant-id, desired-time: desired-time }))))
      (customer-entries (default-to (list) (get waitlist-ids (map-get? customer-waitlist { customer: customer }))))
    )
    (asserts! (get is-active restaurant) err-restaurant-not-active)
    (asserts! (> desired-time current-height) err-invalid-time)
    (asserts! (> party-size u0) err-invalid-time)
    (asserts! (is-none (index-of existing-waitlist waitlist-id)) err-already-on-waitlist)
    
    (map-set waitlist-entries
      { waitlist-id: waitlist-id }
      {
        restaurant-id: restaurant-id,
        customer: customer,
        desired-time: desired-time,
        party-size: party-size,
        created-at: current-height,
        status: "active",
        priority: (len existing-waitlist)
      }
    )
    
    (let
      (
        (updated-restaurant-waitlist (unwrap! (as-max-len? (append existing-waitlist waitlist-id) u100) err-waitlist-full))
        (updated-customer-waitlist (unwrap! (as-max-len? (append customer-entries waitlist-id) u20) err-waitlist-full))
      )
      (map-set restaurant-waitlist
        { restaurant-id: restaurant-id, desired-time: desired-time }
        { waitlist-ids: updated-restaurant-waitlist }
      )
      
      (map-set customer-waitlist
        { customer: customer }
        { waitlist-ids: updated-customer-waitlist }
      )
    )
    
    (var-set next-waitlist-id (+ waitlist-id u1))
    (ok waitlist-id)
  )
)

(define-public (leave-waitlist (waitlist-id uint))
  (let
    (
      (entry (unwrap! (map-get? waitlist-entries { waitlist-id: waitlist-id }) err-waitlist-not-found))
      (customer (get customer entry))
    )
    (asserts! (is-eq tx-sender customer) err-unauthorized)
    (asserts! (is-eq (get status entry) "active") err-not-on-waitlist)
    
    (map-set waitlist-entries
      { waitlist-id: waitlist-id }
      (merge entry { status: "withdrawn" })
    )
    
    (ok true)
  )
)

(define-public (notify-from-waitlist (waitlist-id uint))
  (let
    (
      (entry (unwrap! (map-get? waitlist-entries { waitlist-id: waitlist-id }) err-waitlist-not-found))
      (restaurant (unwrap! (map-get? restaurants { restaurant-id: (get restaurant-id entry) }) err-not-found))
      (restaurant-owner (get owner restaurant))
    )
    (asserts! (is-eq tx-sender restaurant-owner) err-unauthorized)
    (asserts! (is-eq (get status entry) "active") err-not-on-waitlist)
    
    (map-set waitlist-entries
      { waitlist-id: waitlist-id }
      (merge entry { status: "notified" })
    )
    
    (ok true)
  )
)

(define-public (convert-waitlist-to-reservation (waitlist-id uint) (reservation-time uint))
  (let
    (
      (entry (unwrap! (map-get? waitlist-entries { waitlist-id: waitlist-id }) err-waitlist-not-found))
      (restaurant (unwrap! (map-get? restaurants { restaurant-id: (get restaurant-id entry) }) err-not-found))
      (restaurant-owner (get owner restaurant))
      (customer (get customer entry))
      (reservation-id (var-get next-reservation-id))
      (current-height stacks-block-height)
      (deposit-amount (get deposit-amount restaurant))
    )
    (asserts! (is-eq tx-sender restaurant-owner) err-unauthorized)
    (asserts! (is-eq (get status entry) "notified") err-not-on-waitlist)
    (asserts! (> reservation-time current-height) err-invalid-time)
    
    (map-set waitlist-entries
      { waitlist-id: waitlist-id }
      (merge entry { status: "converted" })
    )
    
    (map-set reservations
      { reservation-id: reservation-id }
      {
        restaurant-id: (get restaurant-id entry),
        customer: customer,
        deposit-paid: u0,
        reservation-time: reservation-time,
        created-at: current-height,
        status: "pending",
        party-size: (get party-size entry)
      }
    )
    
    (let
      (
        (existing-reservations (default-to (list) (get reservation-ids (map-get? customer-reservations { customer: customer, restaurant-id: (get restaurant-id entry) }))))
        (updated-reservations (unwrap! (as-max-len? (append existing-reservations reservation-id) u50) err-insufficient-funds))
      )
      (map-set customer-reservations
        { customer: customer, restaurant-id: (get restaurant-id entry) }
        { reservation-ids: updated-reservations }
      )
    )
    
    (map-set restaurants
      { restaurant-id: (get restaurant-id entry) }
      (merge restaurant { total-reservations: (+ (get total-reservations restaurant) u1) })
    )
    
    (var-set next-reservation-id (+ reservation-id u1))
    (ok reservation-id)
  )
)

(define-read-only (get-waitlist-entry (waitlist-id uint))
  (map-get? waitlist-entries { waitlist-id: waitlist-id })
)

(define-read-only (get-restaurant-waitlist (restaurant-id uint) (desired-time uint))
  (map-get? restaurant-waitlist { restaurant-id: restaurant-id, desired-time: desired-time })
)

(define-read-only (get-customer-waitlist (customer principal))
  (map-get? customer-waitlist { customer: customer })
)

(define-read-only (get-waitlist-position (waitlist-id uint))
  (match (map-get? waitlist-entries { waitlist-id: waitlist-id })
    entry (some (+ (get priority entry) u1))
    none
  )
)

(define-read-only (count-active-waitlist (restaurant-id uint) (desired-time uint))
  (let
    (
      (waitlist-data (map-get? restaurant-waitlist { restaurant-id: restaurant-id, desired-time: desired-time }))
    )
    (match waitlist-data
      data (len (get waitlist-ids data))
      u0
    )
  )
)

(define-read-only (is-on-waitlist (customer principal) (restaurant-id uint) (desired-time uint))
  (let
    (
      (waitlist-data (map-get? restaurant-waitlist { restaurant-id: restaurant-id, desired-time: desired-time }))
      (customer-data (map-get? customer-waitlist { customer: customer }))
    )
    (match waitlist-data
      restaurant-list (match customer-data
        customer-list (let
          (
            (restaurant-ids (get waitlist-ids restaurant-list))
            (customer-ids (get waitlist-ids customer-list))
          )
          (is-some (fold check-waitlist-match customer-ids none))
        )
        false
      )
      false
    )
  )
)

(define-private (check-waitlist-match (waitlist-id uint) (found (optional uint)))
  (if (is-some found)
    found
    (match (map-get? waitlist-entries { waitlist-id: waitlist-id })
      entry (if (is-eq (get status entry) "active")
        (some waitlist-id)
        none
      )
      none
    )
  )
)
