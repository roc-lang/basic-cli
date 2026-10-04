## Build a small full-screen snake game using terminal raw mode.
app [main!] { pf: platform "../platform/main.roc" }

import pf.OsStr
import pf.Stdin
import pf.Stdout
import pf.Tty

Position : { x : I64, y : I64 }

Snake : { first : Position, rest : List(Position) }

Direction : { dx : I64, dy : I64 }

GameState : {
	snake : Snake,
	food : Position,
	direction : Direction,
	game_over : Bool,
}

initial_state : GameState
initial_state = {
	snake: { first: { x: 10, y: 10 }, rest: [{ x: 9, y: 10 }, { x: 8, y: 10 }] },
	food: { x: 15, y: 15 },
	direction: right,
	game_over: Bool.False,
}

grid_size : I64
grid_size = 20

up : Direction
up = { dx: 0, dy: -1 }

down : Direction
down = { dx: 0, dy: 1 }

left : Direction
left = { dx: -1, dy: 0 }

right : Direction
right = { dx: 1, dy: 0 }

init_snake_len : U64
init_snake_len = snake_len(initial_state.snake)

main! : List(OsStr) => Try({}, _)
main! = |args| {
	Tty.enable_raw_mode!()
	game_result = game_loop!(initial_state_from_os_strs(args))
	Tty.disable_raw_mode!()

	game_result?
	Stdout.line!("\n--- Game Over ---")?
	Ok({})
}

initial_state_from_os_strs : List(OsStr) -> GameState
initial_state_from_os_strs = |args| {
	# Avoid specializing the renderer with a fully known initial state; the
	# current compiler postcheck panics on that path.
	has_args = args.len() > 0
	{ ..initial_state, game_over: has_args and Bool.not(has_args) }
}

game_loop! : GameState => Try({}, _)
game_loop! = |state| {
	if state.game_over {
		Ok({})
	} else {
		draw_game!(state)?

		input_bytes = Stdin.bytes!()?
		new_state = update_game(apply_input(state, input_bytes))

		game_loop!(new_state)
	}
}

apply_input : GameState, List(U8) -> GameState
apply_input = |state, input_bytes| {
	for byte in input_bytes {
		return apply_input_byte(state, byte)
	}

	state
}

apply_input_byte : GameState, U8 -> GameState
apply_input_byte = |state, byte|
	if byte == 119 {
		{ ..state, direction: up }
	} else if byte == 115 {
		{ ..state, direction: down }
	} else if byte == 97 {
		{ ..state, direction: left }
	} else if byte == 100 {
		{ ..state, direction: right }
	} else if byte == 113 {
		{ ..state, game_over: Bool.True }
	} else {
		state
	}

update_game : GameState -> GameState
update_game = |state| {
	if state.game_over {
		state
	} else {
		new_head = move_head(state.snake.first, state.direction)

		if hit_wall(new_head) or snake_contains(state.snake, new_head) {
			{ ..state, game_over: Bool.True }
		} else if new_head == state.food {
			new_snake = snake_prepend(state.snake, new_head)
			new_food = { x: (new_head.x + 3) % grid_size, y: (new_head.y + 3) % grid_size }

			{ ..state, snake: new_snake, food: new_food }
		} else {
			grown = snake_prepend(state.snake, new_head)
			moved = { first: grown.first, rest: List.drop_last(grown.rest, 1) }

			{ ..state, snake: moved }
		}
	}
}

hit_wall : Position -> Bool
hit_wall = |pos|
	pos.x < 0 or pos.x >= grid_size or pos.y < 0 or pos.y >= grid_size

move_head : Position, Direction -> Position
move_head = |head, direction|
	{ x: head.x + direction.dx, y: head.y + direction.dy }

draw_game! : GameState => Try({}, _)
draw_game! = |state| {
	clear_screen!()?

	Stdout.line!("\nControls: W A S D to move, Q to quit\n\r")?
	Stdout.line!("Score: ${(snake_len(state.snake) - init_snake_len).to_str()}\r")?

	rendered_game_str = draw_game_pure(state)
	Stdout.line!("${rendered_game_str}\r")
}

draw_game_pure : GameState -> Str
draw_game_pure = |state|
	draw_rows(state, 0, [])

draw_rows : GameState, I64, List(Str) -> Str
draw_rows = |state, yy, rows| {
	if yy >= grid_size {
		Str.join_with(rows, "\r\n")
	} else {
		draw_rows(state, yy + 1, rows.append(draw_row(state, yy)))
	}
}

draw_row : GameState, I64 -> Str
draw_row = |state, yy|
	draw_cells(state, yy, 0, [])

draw_cells : GameState, I64, I64, List(Str) -> Str
draw_cells = |state, yy, xx, cells| {
	if xx >= grid_size {
		Str.join_with(cells, "")
	} else {
		pos = { x: xx, y: yy }
		cell = if pos == state.snake.first {
			"O"
		} else if positions_contains(state.snake.rest, pos) {
			"o"
		} else if pos == state.food {
			"*"
		} else {
			"."
		}

		draw_cells(state, yy, xx + 1, cells.append(cell))
	}
}

clear_screen! : () => Try({}, _)
clear_screen! = || Stdout.write!("\u(001b)[2J\u(001b)[H")

snake_contains : Snake, Position -> Bool
snake_contains = |snake, pos|
	snake.first == pos or positions_contains(snake.rest, pos)

positions_contains : List(Position), Position -> Bool
positions_contains = |positions, pos| {
	for current in positions {
		if current == pos {
			return Bool.True
		}
	}

	Bool.False
}

snake_prepend : Snake, Position -> Snake
snake_prepend = |snake, pos|
	{ first: pos, rest: List.prepend(snake.rest, snake.first) }

snake_len : Snake -> U64
snake_len = |snake|
	1 + snake.rest.len()

initial_grid = {
	\\....................
	\\....................
	\\....................
	\\....................
	\\....................
	\\....................
	\\....................
	\\....................
	\\....................
	\\....................
	\\........ooO.........
	\\....................
	\\....................
	\\....................
	\\....................
	\\...............*....
	\\....................
	\\....................
	\\....................
	\\....................
}

moved_down_grid = {
	\\....................
	\\....................
	\\....................
	\\....................
	\\....................
	\\....................
	\\....................
	\\....................
	\\....................
	\\....................
	\\.........oo.........
	\\..........O.........
	\\....................
	\\....................
	\\....................
	\\...............*....
	\\....................
	\\....................
	\\....................
	\\....................
}
