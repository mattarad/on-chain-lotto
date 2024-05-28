# Provably Random Raffle Contracts
**part of the cyfrin.io foundry course**

## About
This code is to create a provably random smart contract lottery.

## What we want it to do?

1. Users enter by purchasing a ticket
    1. The winner of the draw gets the fees
2. After X period of time, the lotto will automatically draw a winner
    1. This will be done programatically
3. Using Chainlink VRF & Chainlink Automation
    1. Chainlink VRF -> Randomness
    2. Chainlink Automation -> Time based trigger
