app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdin
import pf.Stdout
import pf.Tty
import pf.Arg exposing [Arg]

# To run this example: check the README.md in this folder

# If you want to make a full screen terminal app, you probably want to switch the terminal to [raw mode](https://en.wikipedia.org/wiki/Terminal_mode).
# Here we demonstrate `Tty.enable_raw_mode!` and `Tty.disable_raw_mode!` with a simple snake game.

Position : { x : I64, y : I64 }

GameState : {
    snake_lst : NonEmptyList,
    food_pos : Position,
    direction : [Up, Down, Left, Right],
    game_over : Bool,
}

# The snake list should never be empty, so we use a non-empty list.
# Typically we'd use head and tail, but this would be confusing with the snake's head and tail later on :)
NonEmptyList : { first : Position, rest : List Position }

initial_state = {
    snake_lst: { first: { x: 10, y: 10 }, rest: [{ x: 9, y: 10 }, { x: 8, y: 10 }] },
    food_pos: { x: 15, y: 15 },
    direction: Right,
    game_over: Bool.false,
}

# Keep this above 15 for the initial food_pos
grid_size = 20

init_snake_len = len(initial_state.snake_lst)

main! : List Arg => Result {} _
main! = |_args|
    Tty.enable_raw_mode!({})

    game_loop!(initial_state)?

    Tty.disable_raw_mode!({})
    Stdout.line!("\n--- Game Over ---")

game_loop! : GameState => Result {} _
game_loop! = |state|
    if state.game_over then
        Ok({})
    else
        draw_game!(state)?

        # Check keyboard input
        input_bytes = Stdin.bytes!({})?

        partial_new_state =
            when input_bytes is
                ['w'] -> { state & direction: Up }
                ['s'] -> { state & direction: Down }
                ['a'] -> { state & direction: Left }
                ['d'] -> { state & direction: Right }
                ['q'] -> { state & game_over: Bool.true }
                _ -> state

        new_state = update_game(partial_new_state)
        game_loop!(new_state)

update_game : GameState -> GameState
update_game = |state|
    if state.game_over then
        state
    else
        snake_head_pos = state.snake_lst.first
        new_head_pos = move_head(snake_head_pos, state.direction)

        new_state =
            # Check wall collision
            if new_head_pos.x < 0 or new_head_pos.x >= grid_size or new_head_pos.y < 0 or new_head_pos.y >= grid_size then
                { state & game_over: Bool.true }

            # Check self collision
            else if contains(state.snake_lst, new_head_pos) then
                { state & game_over: Bool.true }
            
            # Check food collision
            else if new_head_pos == state.food_pos then
                new_snake_lst = prepend(state.snake_lst, new_head_pos)

                new_food_pos = { x: (new_head_pos.x + 3) % grid_size, y: (new_head_pos.y + 3) % grid_size }

                { state & snake_lst: new_snake_lst, food_pos: new_food_pos }
            
            # No collision; move the snake
            else
                new_snake_lst =
                    prepend(state.snake_lst, new_head_pos)
                    |> |snake_lst| { first: snake_lst.first, rest: List.drop_last(snake_lst.rest, 1) }

                { state & snake_lst: new_snake_lst }

        new_state

move_head : Position, [Down, Left, Right, Up] -> Position
move_head = |head, direction|
    when direction is
        Up -> { head & y: head.y - 1 }
        Down -> { head & y: head.y + 1 }
        Left -> { head & x: head.x - 1 }
        Right -> { head & x: head.x + 1 }

draw_game! : GameState => Result {} _
draw_game! = |state|
    clear_screen!({})?

    Stdout.line!("\nControls: W A S D to move, Q to quit\n\r")?

    # \r to fix indentation because we're in raw mode
    Stdout.line!("Score: ${Num.to_str(len(state.snake_lst) - init_snake_len)}\r")?

    rendered_game_str = draw_game_pure(state)

    Stdout.line!("${rendered_game_str}\r")

draw_game_pure : GameState -> Str
draw_game_pure = |state|
    List.range({ start: At 0, end: Before grid_size })
    |> List.map(
        |yy|
            line =
                List.range({ start: At 0, end: Before grid_size })
                |> List.map(
                    |xx|
                        pos = { x: xx, y: yy }
                        if contains(state.snake_lst, pos) then
                            if pos == state.snake_lst.first then
                                "O" # Snake head
                            else
                                "o" # Snake body
                        else if pos == state.food_pos then
                            "*" # food_pos
                        else
                            ".", # Empty space
                )
                |> Str.join_with("")

            line,
    )
    |> Str.join_with("\r\n")

clear_screen! = |{}|
    Stdout.write!("\u(001b)[2J\u(001b)[H") # ANSI escape codes to clear screen

# NonEmptyList helpers

contains : NonEmptyList, Position -> Bool
contains = |list, pos|
    list.first == pos or List.contains(list.rest, pos)

prepend : NonEmptyList, Position -> NonEmptyList
prepend = |list, pos|
    { first: pos, rest: List.prepend(list.rest, list.first) }

len : NonEmptyList -> U64
len = |list|
    1 + List.len(list.rest)

# Tests

expect
    grid_size == 20 # The tests below assume a grid size of 20

expect
    initial_grid = draw_game_pure(initial_state)
    expected_grid =
        """
        ....................\r
        ....................\r
        ....................\r
        ....................\r
        ....................\r
        ....................\r
        ....................\r
        ....................\r
        ....................\r
        ....................\r
        ........ooO.........\r
        ....................\r
        ....................\r
        ....................\r
        ....................\r
        ...............*....\r
        ....................\r
        ....................\r
        ....................\r
        ....................
        """

    initial_grid == expected_grid

# Test moving down
expect
    new_state = update_game({ initial_state & direction: Down })
    new_grid = draw_game_pure(new_state)

    expected_grid =
    """
    ....................\r
    ....................\r
    ....................\r
    ....................\r
    ....................\r
    ....................\r
    ....................\r
    ....................\r
    ....................\r
    ....................\r
    .........oo.........\r
    ..........O.........\r
    ....................\r
    ....................\r
    ....................\r
    ...............*....\r
    ....................\r
    ....................\r
    ....................\r
    ....................
    """

    new_grid == expected_grid
