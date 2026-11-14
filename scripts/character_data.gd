class_name CharacterData
extends Resource
## Описание одного персонажа для экрана «О персонажах».

## Имя, которое видит игрок.
@export var display_name: String = ""
## Кто он в команде: пилот, гид и т. п.
@export var role: String = ""
## Пара фраз о персонаже.
@export_multiline var description: String = ""
## Портрет. Если не задан, вместо него рисуются инициалы.
@export var portrait: Texture2D
## Цвет акцентов карточки.
@export var accent_color: Color = Color(0.35, 0.85, 1.0)
