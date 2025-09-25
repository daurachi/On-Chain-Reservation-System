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

(define-data-var next-restaurant-id uint u1)
(define-data-var next-reservation-id uint u1)

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
