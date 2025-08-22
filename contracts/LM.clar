;; Liquidity Mining Contract
;; Bootstrap liquidity incentives with emission schedules
;; Rewards users for providing liquidity with token emissions

;; Define the reward tokenQ
(define-fungible-token liquidity-reward)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-amount (err u101))
(define-constant err-no-liquidity (err u102))
(define-constant err-mining-not-active (err u103))

;; Contract state variables
(define-data-var mining-active bool false)
(define-data-var emission-rate uint u100) ;; tokens per block per unit of liquidity
(define-data-var total-liquidity uint u0)
(define-data-var last-update-block uint u0)

;; Track user liquidity positions and rewards
(define-map user-liquidity principal uint)
(define-map user-rewards principal uint)
(define-map user-last-claim-block principal uint)

;; Function 1: Stake liquidity and start earning rewards
(define-public (stake-liquidity (amount uint))
  (begin
    (asserts! (var-get mining-active) err-mining-not-active)
    (asserts! (> amount u0) err-invalid-amount)
    
    ;; Update rewards before changing liquidity position
    (try! (update-user-rewards tx-sender))
    
    ;; Transfer STX as liquidity stake
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Update user liquidity position
    (map-set user-liquidity tx-sender 
             (+ (default-to u0 (map-get? user-liquidity tx-sender)) amount))
    
    ;; Update total liquidity
    (var-set total-liquidity (+ (var-get total-liquidity) amount))
    
    ;; Set user's last claim block
    (map-set user-last-claim-block tx-sender block-height)
    
    (ok amount)))

;; Function 2: Claim accumulated mining rewards
(define-public (claim-rewards)
  (begin
    (asserts! (var-get mining-active) err-mining-not-active)
    (asserts! (> (default-to u0 (map-get? user-liquidity tx-sender)) u0) err-no-liquidity)
    
    ;; Update rewards before claiming
    (try! (update-user-rewards tx-sender))
    
    (let ((pending-rewards (default-to u0 (map-get? user-rewards tx-sender))))
      (asserts! (> pending-rewards u0) err-invalid-amount)
      
      ;; Mint reward tokens to user
      (try! (ft-mint? liquidity-reward pending-rewards tx-sender))
      
      ;; Reset user rewards
      (map-set user-rewards tx-sender u0)
      
      ;; Update last claim block
      (map-set user-last-claim-block tx-sender block-height)
      
      (ok pending-rewards))))

;; Helper function: Update user rewards based on emission schedule
(define-private (update-user-rewards (user principal))
  (let ((user-liq (default-to u0 (map-get? user-liquidity user)))
        (last-claim (default-to block-height (map-get? user-last-claim-block user)))
        (blocks-elapsed (- block-height last-claim))
        (total-liq (var-get total-liquidity)))
    
    (if (and (> user-liq u0) (> total-liq u0) (> blocks-elapsed u0))
        (let ((reward-per-block (/ (* (var-get emission-rate) user-liq) total-liq))
              (new-rewards (* reward-per-block blocks-elapsed)))
          (map-set user-rewards user 
                   (+ (default-to u0 (map-get? user-rewards user)) new-rewards))
          (ok true))
        (ok true))))

;; Read-only functions
(define-read-only (get-user-liquidity (user principal))
  (ok (default-to u0 (map-get? user-liquidity user))))

(define-read-only (get-user-rewards (user principal))
  (ok (default-to u0 (map-get? user-rewards user))))

(define-read-only (get-total-liquidity)
  (ok (var-get total-liquidity)))

(define-read-only (get-emission-rate)
  (ok (var-get emission-rate)))

(define-read-only (is-mining-active)
  (ok (var-get mining-active)))

;; Owner functions
(define-public (start-mining)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set mining-active true)
    (var-set last-update-block block-height)
    (ok true)))

(define-public (set-emission-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set emission-rate new-rate)
    (ok true)))