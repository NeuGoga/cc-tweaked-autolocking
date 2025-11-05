An advanced, high-precision auto-turret script designed for CC:Tweaked and the Create Big Cannons mod. This project features a sophisticated ballistic calculator, a predictive aiming system with active braking, and a full user interface for target management.

## Features

- **Advanced Ballistic Prediction:** Accurately calculates projectile trajectory, accounting for gravity and linear drag.
- **Predictive Aiming:** A two-stage algorithm performs a high-speed predictive turn and a slow, precise final adjustment to eliminate wiggle and maximize accuracy.
- **Dynamic Projectile Speed:** Uses a lookup table based on cannon barrel length for perfect calculations.
- **Full User Interface:** An in-game monitor provides engagement controls, a target list management system, and a reset button.
- **Network Synchronization:** A secure, encrypted and modem-based system allows a single remote to control multiple turrets in unison.
- **Auto-Updating**
- **Two Versions:**
    - `entity_turret.lua`: The primary version, for targeting any entity (mobs, players, etc.) using an Environment Detector.
    - `player_turret.lua`: A simplified version that targets only players, for setups without an Environment Detector.

## Files

- **`entity_turret.lua`**: The main script. Requires the **Advanced Peripherals** mod for the `environmentDetector`.
- **`player_turret.lua`**: A version of the script that uses the base `playerDetector` peripheral.

## Setup Requirements

### In-Game Build:
- A Create Big Cannons turret built with **Rotation Speed Controllers** for both Yaw and Pitch.
- A **Computer** with peripherals attached.
- A **Redstone Integrator/Relay** for fire control and rotation locking.
- A **Block Reader** pointed at the main Cannon Mount block.
- An **Environment Detector** (for `entity_turret.lua`) or a **Player Detector** (for `player_turret.lua`).
- A **Monitor**.
- A **Wireless Modem**.

### How to Setup:

- **Guide:** https://www.youtube.com/watch?v=qtvYkLEvNfg

## How to Use

- **Engage/Disengage:** Click the button on the top-left of the monitor.
- **Target Management:**
    - The left column shows all nearby entities. Click a name to add it to the **Target List**.
    - The right column shows the **Target List**. The turret will only fire at entities on this list. Click a name to remove it.
- **Reset:** Click the "Reset" button to wipe all configuration and start the setup wizard again.
