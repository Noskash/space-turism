class_name CharacterData
extends Resource
## One character for the CREW screen.

## The name the player sees.
@export var display_name: String = ""
## Their job on the team: pilot, guide, etc.
@export var role: String = ""
## A couple of sentences about them.
@export_multiline var description: String = ""
## Portrait. If not set, initials are drawn instead.
@export var portrait: Texture2D
## The card's accent colour.
@export var accent_color: Color = Color(0.35, 0.85, 1.0)
