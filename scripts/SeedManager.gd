extends Node

## SeedManager - Global Singleton for Deterministic Random Number Generation
## Provides seeded RNG for consistent gameplay experiences and replayability

# The active seed value
var current_seed: int = 0

# RandomNumberGenerator instance for deterministic randomness
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	# Initialize with a random seed by default
	# This will be overridden when loading a saved game or setting a specific seed
	generate_new_seed()
	print("SeedManager initialized with seed: ", current_seed)

## Initialize the RNG with a specific seed
func initialize_seed(seed_value: int) -> void:
	current_seed = seed_value
	rng.seed = seed_value
	print("SeedManager seed set to: ", current_seed)

## Generate and set a new random seed
func generate_new_seed() -> int:
	# Use system time to generate a unique seed
	current_seed = Time.get_ticks_msec() #42112
	rng.seed = current_seed
	return current_seed

## Get the current active seed
func get_current_seed() -> int:
	return current_seed

## Generate a random integer (replacement for global randi())
func randi() -> int:
	return rng.randi()

## Generate a random float between 0.0 and 1.0 (replacement for global randf())
func randf() -> float:
	return rng.randf()

## Generate a random integer in a range [from, to] inclusive
func randi_range(from: int, to: int) -> int:
	return rng.randi_range(from, to)

## Generate a random float in a range [from, to]
func randf_range(from: float, to: float) -> float:
	return rng.randf_range(from, to)

## Shuffle an array deterministically based on the current seed
## Note: This modifies the array in place
func shuffle_array(array: Array) -> void:
	# Fisher-Yates shuffle algorithm using our seeded RNG
	var n = array.size()
	for i in range(n - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var temp = array[i]
		array[i] = array[j]
		array[j] = temp

## Get a random element from an array
func pick_random(array: Array):
	if array.is_empty():
		return null
	return array[rng.randi_range(0, array.size() - 1)]
