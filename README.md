# 🍽️ On-Chain Reservation System

A Clarity smart contract that enables restaurants to take STX deposits for reservations, reducing no-shows while providing refundable cancellations within a specified time window.

## 🚀 Features

- 🏪 **Restaurant Registration**: Restaurants can register and set deposit amounts & cancellation policies
- 💰 **STX Deposits**: Customers pay deposits in STX when making reservations  
- ⏰ **Timed Cancellations**: Refundable cancellations within restaurant-defined time windows
- ✅ **Reservation Confirmation**: Restaurants confirm attendance and receive deposits
- 🚫 **No-Show Handling**: Automatic deposit forfeiture for customer no-shows
- 📊 **Analytics**: Track restaurant revenue and reservation statistics

## 📋 Contract Functions

### Public Functions

| Function | Description | Parameters |
|----------|-------------|------------|
| `register-restaurant` | Register a new restaurant | `name`, `deposit-amount`, `cancellation-window` |
| `make-reservation` | Make a reservation with STX deposit | `restaurant-id`, `reservation-time`, `party-size` |
| `cancel-reservation` | Cancel reservation and get refund (if within window) | `reservation-id` |
| `confirm-reservation` | Restaurant confirms customer attendance | `reservation-id` |
| `handle-no-show` | Restaurant marks no-show and claims deposit | `reservation-id` |
| `update-restaurant-settings` | Update deposit amount and cancellation window | `deposit-amount`, `cancellation-window` |
| `toggle-restaurant-status` | Activate/deactivate restaurant | - |

### Read-Only Functions

| Function | Description | Returns |
|----------|-------------|---------|
| `get-restaurant` | Get restaurant details | Restaurant data |
| `get-reservation` | Get reservation details | Reservation data |
| `get-restaurant-by-owner` | Get restaurant owned by principal | Restaurant data |
| `can-cancel-reservation` | Check if reservation can be cancelled | Boolean |
| `get-contract-balance` | Get total STX held by contract | Balance in microSTX |
| `get-restaurant-stats` | Get restaurant statistics | Stats object |

## 🎯 Usage Examples

### For Restaurants

```clarity
;; 1. Register your restaurant (1 STX deposit, 144 blocks cancellation window ~24 hours)
(contract-call? .On-Chain-Reservation-System register-restaurant "Mario's Pizza" u1000000 u144)

;; 2. Confirm a customer showed up (transfers deposit to restaurant)
(contract-call? .On-Chain-Reservation-System confirm-reservation u1)

;; 3. Handle no-show (transfers deposit to restaurant)
(contract-call? .On-Chain-Reservation-System handle-no-show u2)

;; 4. Update settings (2 STX deposit, 72 blocks window ~12 hours)
(contract-call? .On-Chain-Reservation-System update-restaurant-settings u2000000 u72)
```

### For Customers

```clarity
;; 1. Make reservation (auto-pays required deposit)
(contract-call? .On-Chain-Reservation-System make-reservation u1 u1000 u4)

;; 2. Cancel reservation within time window (gets refund)
(contract-call? .On-Chain-Reservation-System cancel-reservation u1)

;; 3. Check if you can still cancel
(contract-call? .On-Chain-Reservation-System can-cancel-reservation u1)
```

## 💡 How It Works

1. **🏪 Restaurant Setup**: Restaurant owners register with their desired deposit amount and cancellation window
2. **📅 Reservation**: Customers make reservations by paying the STX deposit 
3. **⏰ Cancellation Window**: Customers can cancel and get full refunds within the time window
4. **✅ Confirmation**: Restaurants confirm attendance and receive the deposit
5. **🚫 No-Shows**: After reservation time passes, restaurants can claim deposits from no-shows

## 🔧 Technical Details

- **Deposit Amounts**: Set by each restaurant in microSTX (1 STX = 1,000,000 microSTX)
- **Time Windows**: Measured in Stacks blocks (~10 minutes per block)  
- **Block Height**: Uses `stacks-block-height` for timing calculations
- **Security**: Only restaurant owners can confirm/handle no-shows, only customers can cancel their own reservations

## 🏗️ Deployment

1. Deploy with Clarinet:
```bash
clarinet check
clarinet test
clarinet deploy
```

2. Interact via Clarinet console or web interface

## 🤝 Contributing

This contract is designed to be simple and focused. Pull requests welcome for bug fixes and improvements!

## 📜 License

MIT License - feel free to fork and adapt for your needs!
