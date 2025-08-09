const FeeAmount = {
  LOW: 100,
  MEDIUM: 500,
  HIGH: 3000,
}

const TICK_SPACINGS = {
  [FeeAmount.LOW]: 1,
  [FeeAmount.MEDIUM]: 10,
  [FeeAmount.HIGH]: 60,
}

module.exports = {
  FeeAmount,
  TICK_SPACINGS
}