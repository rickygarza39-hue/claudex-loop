class_name Tuning
extends RefCounted
## Every balance number in one place. Times are in seconds, distances in metres,
## money in company scrip ($). Change values here and restart the match.

# ---- Match ---------------------------------------------------------------------
const DUOS := 5
const KILLERS := 3
const MAP_CELLS := 4               # map is MAP_CELLS x MAP_CELLS districts of 28x28 tiles
const KILLER_RELEASE := 40.0       # killers are held at the Nest this long
const FINAL_PUSH_AT := 20.0 * 60.0 # "final push" announcement
const PURGE_AT := 27.0 * 60.0      # hard end: the company purges the town
const WORSE_TRAP_BONUS := 60       # money for the duo that drew the worse trap
const CELL_PICK_TIME := 16.0       # seconds of lock picking (two people pick twice as fast)
const WORSE_LEVER_TIME := 9.0      # worse trap: both levers held together this long

# ---- Movement (m/s) --------------------------------------------------------------
const SURV_WALK := 2.9
const SURV_RUN := 4.1
const SURV_CROUCH := 1.7
const SURV_CRAWL := 0.9
const SURV_SQUEEZE := 2.0
const SURV_WOUND_BOOST := 6.2
const SURV_WOUND_BOOST_TIME := 2.6
const WATER_MULT := 0.72
const KILLER_SPEED := [4.35, 4.15, 4.25]   # Tracker, Brute, Lurker
const ELITE_SPEED := 3.75
const ELITE_SIGHT := 11.0
const ELITE_WINDUP := 0.55
const ELITE_RECOVER_HIT := 2.9
const HUSK_SPEED := 4.05
const SURV_RADIUS := 0.32
const KILLER_RADIUS := [0.38, 0.55, 0.36]

# ---- Senses ---------------------------------------------------------------------
const SURV_SIGHT := 20.0
const SURV_SIGHT_DARK := 11.0      # during Blackout
const ITEM_SPOT_RANGE := 18.0      # survivors notice items within this range (line of sight)
const KILLER_SIGHT := 13.5
const KILLER_SIGHT_CROUCHED := 7.0
const BOT_REACTION := 0.55         # bot killers notice a survivor only after seeing them this long
const BOT_CHASE_GIVEUP := 35.0     # bot killers drop a chase that lands no hit for this long
const LURKER_VISIBLE_RANGE := 12.0 # survivors only notice an unspotted Lurker this close
const TERROR_RADIUS := 24.0        # heartbeat for non-Lurker killers
const NOISE_RUN := 8.0
const NOISE_BUILD := 18.0
const NOISE_STEAL := 26.0
const NOISE_SMASH := 30.0
const NOISE_GENERATOR := 45.0
const TRAIL_INTERVAL := 1.4        # metres between footprints
const TRAIL_LIFETIME := 26.0
const BLOOD_LIFETIME := 34.0

# ---- Combat ---------------------------------------------------------------------
const ATTACK_RANGE := 2.1
const ATTACK_ARC_DEG := 100.0
const ATTACK_WINDUP := 0.42
const ATTACK_RECOVER_HIT := 2.3
const ATTACK_RECOVER_MISS := 1.05
const PARRY_WINDOW := 0.12         # GDD: "about a tenth of a second"
const PARRY_COOLDOWN := 1.1
const PARRY_REWARD := 20
const PARRY_REWARD_LOCKOUT := 45.0 # parry only pays once per killer per this long
const CATCH_TIME := 3.5
const KNOCKDOWN_STUN := 5.0        # flare gun
const SNARE_HOLD := 3.0
const FLASH_DISORIENT := 4.0
const TRAP_IMMUNITY := 8.0
const BRUTE_STUN_MULT := 0.65      # "extra health": stuns hold the Brute for less
const FLARE_RANGE := 11.0
const FLARE_COUNT := 4             # knockdown items per match
const HOTZONE_SHIFT := 55.0        # killers' vague item hot zones move this often
const HOTZONE_RADIUS := 22.0

# ---- Killer powers ----------------------------------------------------------------
const STALK_TIME := 8.0
const STALK_COOLDOWN := 16.0
const STALK_SPEED := 6.6
const CHARGE_WINDUP := 0.55
const CHARGE_TIME := 1.7
const CHARGE_SPEED := 9.5
const CHARGE_TURN_DEG := 55.0      # degrees per second while charging
const CHARGE_MISS_STUN := 2.0
const CHARGE_METAL_STUN := 3.2
const CHARGE_COOLDOWN := 14.0
const CHARGE_INSTANT_DOWN := false # GDD: "knocks down survivors" — read as a forceful hit, not a one-shot
const CHARGE_HIT_RECOVER := 1.5
const TONGUE_RANGE := 13.0
const TONGUE_SPEED := 32.0
const TONGUE_PULL := 2.8
const TONGUE_COOLDOWN := 26.0
const TONGUE_BREAK_TIME := 0.8
const LURKER_SPOT_TIME := 2.2      # seconds in a survivor's view/floodlight to be "spotted"
const LURKER_SPOTTED_FOR := 9.0
const LURKER_SPOTTED_SLOW := 0.82
const ROUTE_CHARGES := 3
const ROUTE_REFILL_ON_NEST := 1    # answer to the open question: Nest events refill one charge
const SMASH_TIME := 2.2            # boarded passages and cell doors
const TIRE_AFTER := 28.0           # seconds of continuous chasing before a killer tires
const TIRE_TIME := 6.0
const TIRE_MULT := 0.88
const WINDUP_MOVE := 0.85         # speed multiplier while winding up a swing
const TONGUE_RECOVER := 1.6        # Lurker recovery after a tongue lands
const TONGUE_CONSTRICT := 2.5      # a pulled survivor is held this long before taking a hit

# ---- Health / downed -----------------------------------------------------------------
const TURN_TIME := 90.0            # downed -> turns into an elite
const BASE_TURN_BONUS := 120.0     # "about two extra minutes" for reaching your own base
const DAZE_TIME := 10.0
const HEAL_TIME := 10.0
const MEDIC_HEAL_TIME := 4.5
const MEDIC_SELF_HEAL_TIME := 9.0
const REVIVE_TIME := 5.0
const CURE_USE_TIME := 4.0

# ---- Economy ------------------------------------------------------------------------
const START_MONEY := 40
const START_SCRAP := 2
const STAGE_COST := [40, 120, 190]
const STAGE_BUILD_TIME := [16.0, 26.0, 36.0]
const REPAIR_COST_FRAC := 0.15
const REPAIR_TIME := 8.0
const STATION_HP := 300.0
const STATION_DAMAGE_MULT := 0.3  # killers' swings do less to the radio than to walls
const GENERATOR_NOISE_EVERY := 22.0  # a running generator is heard nearby every so often
const REVEAL_ON_STAGE := 35.0      # seconds a base stays revealed after finishing a stage
const CURE_COST := 200
const CURE_STOCK := 5
const CARRY_PARTS := 2
const REWARD_SNARE := 25
const REWARD_FLASH := 25
const REWARD_KNOCKDOWN := 40
const REWARD_HEAL := 12
const REWARD_SAVE := 30            # revive, cure, break a tongue
const REWARD_CHASE_ESCAPE := 15
const BOUNTY_MIN := 40
const CASH_CACHES := 90
const CASH_MIN := 14
const CASH_MAX := 38
const SCRAP_PILES := 65
const SCRAP_PER_PILE := 2
const PART_COUNTS := [7, 6, 6, 6, 6, 6]  # Cable, Fuel, Spark, Circuit, Cell, Dish
const DONATE_STEP := 25

# ---- Shop ---------------------------------------------------------------------------
const SHOP_TERMINALS := 4
const SHOP_OPEN_COUNT := 2         # terminals that open each window
const SHOP_INTERVAL := 300.0
const SHOP_OPEN_TIME := 60.0
const SHOP_WARNING := 20.0
const SHOP_ITEMS := {
	"cure": {"name": "Cure", "cost": CURE_COST, "desc": "Saves a downed survivor from turning. 5 per match, one per person."},
	"medkit": {"name": "Medkit", "cost": 45, "desc": "Heal yourself from wounded instantly."},
	"traps": {"name": "Trap kit", "cost": 35, "desc": "+1 snare and +1 flash trap."},
	"scrap": {"name": "Scrap crate", "cost": 30, "desc": "+4 scrap for your duo."},
	"scanner": {"name": "Part scanner", "cost": 25, "desc": "Reveals the nearest parts your radio needs."},
}

# ---- Radio / helicopter -------------------------------------------------------------
const BASE_RADIUS := 6             # tiles
const BASE_MIN_SPACING := 26       # tiles between base centres
const HELI_ARRIVAL := 90.0
const HELI_BOARD_WINDOW := 15.0
const HELI_MAX_HOVER := 30.0       # hovering cap so killers can't block the landing forever
const HELI_LZ_RADIUS := 7.0
const HELI_SEARCHLIGHT := 4.0      # on landing, killers in the landing zone are blinded this long
const HELI_RESPONSE_RANGE := 70.0  # killer bots further away than this ignore a helicopter call

# ---- Building ----------------------------------------------------------------------
# cost: [scrap, money]; hp; build time
const BUILD := {
	Defs.B.WALL: {"scrap": 2, "money": 0, "hp": 110.0, "time": 2.5},
	Defs.B.DOOR: {"scrap": 3, "money": 0, "hp": 90.0, "time": 3.0},
	Defs.B.BARRICADE: {"scrap": 1, "money": 0, "hp": 45.0, "time": 1.2},
	Defs.B.ALARM: {"scrap": 1, "money": 10, "hp": 20.0, "time": 1.5},
	Defs.B.FLOODLIGHT: {"scrap": 2, "money": 25, "hp": 30.0, "time": 2.0},
	Defs.B.DECOY: {"scrap": 1, "money": 0, "hp": 15.0, "time": 1.2},
	Defs.B.LOCKER: {"scrap": 2, "money": 0, "hp": 60.0, "time": 2.0},
	Defs.B.SNARE: {"scrap": 1, "money": 10, "hp": 10.0, "time": 1.0},
	Defs.B.FLASH: {"scrap": 1, "money": 15, "hp": 10.0, "time": 1.0},
	Defs.B.HATCH: {"scrap": 0, "money": 0, "hp": 999.0, "time": 4.0},
}
const SPIKE_UPGRADE := {"scrap": 1, "money": 30}
const METAL_UPGRADE := {"scrap": 2, "money": 50}
const METAL_HP := 330.0
const SPIKE_STUN := 1.4
const KILLER_STRUCT_DPS := 30.0    # killer hitting a structure (per second of swinging)
const BRUTE_STRUCT_MULT := 2.0
const ENGINEER_BUILD_MULT := 1.6
const MEDIC_BUILD_MULT := 0.7
const ENGINEER_BARRICADE_COOLDOWN := 22.0
const BARRICADE_LIFETIME := 45.0   # quick barricades rot away
const LOCKDOWN_TIME := 20.0
const ALARM_RADIUS := 6.0
const FLOODLIGHT_RADIUS := 9.0
const DECOY_INTERVAL := 7.0
const TRAP_CAPACITY := [2, 2, 6]   # by role
const TRAP_START := [0, 0, 3]      # each trap type at start, by role
const TRAPPER_PLACE_TIME := 0.5
const OTHER_PLACE_TIME := 1.4

# ---- Medic ------------------------------------------------------------------------
const SCENT_MASK_TIME := 20.0
const SCENT_MASK_RADIUS := 7.0
const SCENT_MASK_COOLDOWN := 55.0

# ---- Betrayal -----------------------------------------------------------------------
const STEAL_TIME := 7.0
const THIEF_SEEN_RANGE := 16.0

# ---- Nest ---------------------------------------------------------------------------
const NEST_MAX := 100.0
const NEST_CATCH := 22.0
const NEST_STRUCTURE_BROKEN := 3.0
const NEST_STATION_DAMAGE := 0.08  # per hp
const NEST_STAGE := [9.0, 12.0, 15.0]
const NEST_HELI := 35.0
const NEST_PASSIVE := 0.03         # per second
const NEST_FINAL_PUSH_MULT := 1.5
const NEST_COOLDOWN := 50.0
const BLACKOUT_TIME := 25.0
const PULSE_TIME := 5.0
const SWARM_HUSKS := 4
const SWARM_TIME := 40.0
const JAM_TIME := 20.0

# ---- Elites -------------------------------------------------------------------------
const ELITE_RESPAWN := 30.0
const ELITE_XP_CATCH := 3
const ELITE_XP_ASSIST := 1
const ELITE_XP_PER_LEVEL := 3
const ELITE_MAX_LEVEL := 3
const ELITE_POWER_MULT := 0.6      # elite powers are weaker versions
const ELITES_CAN_CATCH := true     # GDD default; set false to make elites pure pressure
const ELITES_ENABLED := true       # debug: false = caught survivors just spectate
