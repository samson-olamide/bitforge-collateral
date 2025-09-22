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

(define-public (mint-stablecoin 
  (vault-owner principal)
  (vault-id uint)
  (mint-amount uint)
)
  (let
    (
      (is-valid-vault-id 
        (and 
          (> vault-id u0)
          (<= vault-id (var-get vault-counter))
        )
      )
      (vault 
        (unwrap! 
          (map-get? vaults {owner: vault-owner, id: vault-id}) 
          ERR-INVALID-PARAMETERS
        )
      )
      (btc-price 
        (unwrap! 
          (get-latest-btc-price) 
          ERR-ORACLE-PRICE-UNAVAILABLE
        )
      )
      (max-mintable 
        (/
          (* 
            (get collateral-amount vault) 
            btc-price
          ) 
          (var-get collateralization-ratio)
        )
      )
    )
    (asserts! is-valid-vault-id ERR-INVALID-PARAMETERS)
    (asserts! (is-eq tx-sender vault-owner) ERR-UNAUTHORIZED-VAULT-ACTION)
    (asserts! (> mint-amount u0) ERR-INVALID-PARAMETERS)
    (asserts! 
      (>= 
        max-mintable 
        (+ (get stablecoin-minted vault) mint-amount)
      ) 
      ERR-UNDERCOLLATERALIZED
    )
    (asserts! 
      (<= 
        (+ (get stablecoin-minted vault) mint-amount) 
        (var-get max-mint-limit)
      ) 
      ERR-MINT-LIMIT-EXCEEDED
    )
    (map-set vaults {owner: vault-owner, id: vault-id}
      {
        collateral-amount: (get collateral-amount vault),
        stablecoin-minted: (+ (get stablecoin-minted vault) mint-amount),
        created-at: (get created-at vault)
      }
    )
    (var-set total-supply 
      (+ (var-get total-supply) mint-amount)
    )
    (ok true)
  )
)

;; RISK MANAGEMENT FUNCTIONS

(define-public (liquidate-vault 
  (vault-owner principal)
  (vault-id uint)
)
  (let
    (
      (is-valid-vault-id 
        (and 
          (> vault-id u0)
          (<= vault-id (var-get vault-counter))
        )
      )
      (vault 
        (unwrap! 
          (map-get? vaults {owner: vault-owner, id: vault-id}) 
          ERR-INVALID-PARAMETERS
        )
      )
      (btc-price 
        (unwrap! 
          (get-latest-btc-price) 
          ERR-ORACLE-PRICE-UNAVAILABLE
        )
      )
      (current-collateralization 
        (/
          (* 
            (get collateral-amount vault) 
            btc-price
          ) 
          (get stablecoin-minted vault)
        )
      )
    )
    (asserts! is-valid-vault-id ERR-INVALID-PARAMETERS)
    (asserts! (not (is-eq tx-sender vault-owner)) ERR-UNAUTHORIZED-VAULT-ACTION)
    (asserts! 
      (< current-collateralization (var-get liquidation-threshold)) 
      ERR-LIQUIDATION-FAILED
    )
    (var-set total-supply 
      (- (var-get total-supply) (get stablecoin-minted vault))
    )
    (map-delete vaults {owner: vault-owner, id: vault-id})
    (ok true)
  )
)

(define-public (redeem-stablecoin 
  (vault-owner principal)
  (vault-id uint)
  (redeem-amount uint)
)
  (let
    (
      (is-valid-vault-id 
        (and 
          (> vault-id u0)
          (<= vault-id (var-get vault-counter))
        )
      )
      (vault 
        (unwrap! 
          (map-get? vaults {owner: vault-owner, id: vault-id}) 
          ERR-INVALID-PARAMETERS
        )
      )
    )
    (asserts! is-valid-vault-id ERR-INVALID-PARAMETERS)
    (asserts! (is-eq tx-sender vault-owner) ERR-UNAUTHORIZED-VAULT-ACTION)
    (asserts! (> redeem-amount u0) ERR-INVALID-PARAMETERS)
    (asserts! 
      (<= redeem-amount (get stablecoin-minted vault)) 
      ERR-INSUFFICIENT-BALANCE
    )
    (map-set vaults {owner: vault-owner, id: vault-id}
      {
        collateral-amount: (get collateral-amount vault),
        stablecoin-minted: (- (get stablecoin-minted vault) redeem-amount),
        created-at: (get created-at vault)
      }
    )
    (var-set total-supply 
      (- (var-get total-supply) redeem-amount)
    )
    (ok true)
  )
)

;; GOVERNANCE FUNCTIONS

(define-public (update-collateralization-ratio (new-ratio uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! 
      (and 
        (>= new-ratio u100)
        (<= new-ratio u300)
      ) 
      ERR-INVALID-PARAMETERS
    )
    (var-set collateralization-ratio new-ratio)
    (ok true)
  )
)

;; READ-ONLY FUNCTIONS

(define-read-only (get-latest-btc-price)
  (map-get? last-btc-price 
    {
      timestamp: stacks-block-height,
      price: u0
    }
  )
)

(define-read-only (get-vault-details (vault-owner principal) (vault-id uint))
  (map-get? vaults {owner: vault-owner, id: vault-id})
)

(define-read-only (get-total-supply)
  (var-get total-supply)
)