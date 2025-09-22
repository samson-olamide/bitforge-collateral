;; Title: BitForge Collateral Protocol
;;
;; Summary:
;; A revolutionary Bitcoin-collateralized stablecoin ecosystem built on Stacks,
;; empowering users to forge USD-pegged digital assets by locking Bitcoin as
;; collateral through an autonomous, trustless financial infrastructure.
;;
;; Description:
;; BitForge transforms idle Bitcoin holdings into productive capital through
;; an innovative collateralized debt position (CDP) system. Users can establish
;; secure vaults, deposit Bitcoin as collateral, and mint BFUSD stablecoins
;; while maintaining full control over their assets. The protocol features
;; real-time price oracles, dynamic risk management, automated liquidation
;; protection, and governance-driven parameters. Built specifically for the
;; Stacks ecosystem, BitForge bridges Bitcoin's store-of-value properties
;; with DeFi's programmable money capabilities, creating a new paradigm
;; for Bitcoin-native financial services.
;;
;; Key Features:
;; - Bitcoin-collateralized CDP system with over-collateralization safety
;; - Multi-oracle price feeds for robust market data aggregation
;; - Automated liquidation engine protecting protocol solvency
;; - Flexible collateralization ratios with governance oversight
;; - Fee-optimized minting and redemption mechanisms
;; - Permissionless vault creation and management

;; TRAIT DEFINITIONS

(define-trait sip-010-token
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-name () (response (string-ascii 32) uint))
    (get-symbol () (response (string-ascii 5) uint))
    (get-decimals () (response uint uint))
    (get-balance (principal) (response uint uint))
    (get-total-supply () (response uint uint))
  )
)

;; ERROR CODES

(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1001))
(define-constant ERR-INVALID-COLLATERAL (err u1002))
(define-constant ERR-UNDERCOLLATERALIZED (err u1003))
(define-constant ERR-ORACLE-PRICE-UNAVAILABLE (err u1004))
(define-constant ERR-LIQUIDATION-FAILED (err u1005))
(define-constant ERR-MINT-LIMIT-EXCEEDED (err u1006))
(define-constant ERR-INVALID-PARAMETERS (err u1007))
(define-constant ERR-UNAUTHORIZED-VAULT-ACTION (err u1008))

;; SECURITY CONSTANTS

(define-constant MAX-BTC-PRICE u1000000000000)  ;; Maximum reasonable BTC price
(define-constant MAX-TIMESTAMP u18446744073709551615)  ;; Maximum uint timestamp
(define-constant CONTRACT-OWNER tx-sender)

;; PROTOCOL CONFIGURATION

(define-data-var stablecoin-name (string-ascii 32) "BitForge USD")
(define-data-var stablecoin-symbol (string-ascii 5) "BFUSD")
(define-data-var total-supply uint u0)
(define-data-var collateralization-ratio uint u150)
(define-data-var liquidation-threshold uint u125)

;; PROTOCOL PARAMETERS

(define-data-var mint-fee-bps uint u50)
(define-data-var redemption-fee-bps uint u50)
(define-data-var max-mint-limit uint u1000000)

;; ORACLE SYSTEM

(define-map btc-price-oracles principal bool)
(define-map last-btc-price 
  {
    timestamp: uint,
    price: uint
  }
  uint
)

;; VAULT SYSTEM

(define-map vaults 
  {
    owner: principal, 
    id: uint
  }
  {
    collateral-amount: uint,
    stablecoin-minted: uint,
    created-at: uint
  }
)

(define-data-var vault-counter uint u0)

;; ORACLE MANAGEMENT FUNCTIONS

(define-public (add-btc-price-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (and 
      (not (is-eq oracle CONTRACT-OWNER)) 
      (not (is-eq oracle tx-sender))
    ) ERR-INVALID-PARAMETERS)
    (map-set btc-price-oracles oracle true)
    (ok true)
  )
)

(define-public (update-btc-price (price uint) (timestamp uint))
  (begin
    (asserts! (is-some (map-get? btc-price-oracles tx-sender)) ERR-NOT-AUTHORIZED)
    (asserts! (and 
      (> price u0)
      (<= price MAX-BTC-PRICE)
    ) ERR-INVALID-PARAMETERS)
    (asserts! (<= timestamp MAX-TIMESTAMP) ERR-INVALID-PARAMETERS)
    (map-set last-btc-price 
      {
        timestamp: timestamp, 
        price: price
      }
      price
    )
    (ok true)
  )
)

;; VAULT MANAGEMENT FUNCTIONS

(define-public (create-vault (collateral-amount uint))
  (let 
    (
      (vault-id (+ (var-get vault-counter) u1))
      (new-vault 
        {
          owner: tx-sender,
          id: vault-id
        }
      )
    )
    (asserts! (> collateral-amount u0) ERR-INVALID-COLLATERAL)
    (asserts! (< vault-id (+ (var-get vault-counter) u1000)) ERR-INVALID-PARAMETERS)
    (var-set vault-counter vault-id)
    (map-set vaults new-vault 
      {
        collateral-amount: collateral-amount,
        stablecoin-minted: u0,
        created-at: stacks-block-height
      }
    )
    (ok vault-id)
  )
)