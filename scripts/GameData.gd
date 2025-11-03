extends Node

# Persistent starmap data
var star_data: Array[Dictionary] = []
var constellation_data: Array[Dictionary] = []
var has_starmap_data: bool = false

func save_starmap(stars: Array[Dictionary], constellations: Array[Dictionary]):
	star_data = stars.duplicate(true)
	constellation_data = constellations.duplicate(true)
	has_starmap_data = true

func clear_starmap():
	star_data.clear()
	constellation_data.clear()
	has_starmap_data = false
