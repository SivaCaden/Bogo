# BogoSort

A fun Neovim plugin that visualizes the bogosort algorithm in real-time. Watch as the visualizer randomly shuffles numbers until they're sorted—it's hilariously inefficient and entertaining!

## Installation with Lazy.nvim

### Step 1: Create a Plugin Configuration File

Create a new file at `~/.config/nvim/lua/plugins/bogosort.lua`:

```lua
return {
  "SivaCaden/Bogo",
  lazy = true,
  cmd = "BogoSort",
}
```

### Step 2: Make Sure Lazy.nvim Loads Plugins from `lua/plugins/`

If you haven't already, ensure your Neovim configuration loads plugins from the `lua/plugins/` directory. In your main `init.lua`, add:

```lua
require("lazy").setup("plugins")
```

That's it! The plugin will be loaded when you run the `:BogoSort` command.

## Usage

Simply run the command in Neovim:

```vim
:BogoSort
```

A floating window will appear showing a bar chart visualization of the bogosort algorithm in action. The visualizer displays:

- **Bar Chart**: A visual representation of the current array state
- **Shuffle Count**: How many times the array has been shuffled
- **Elapsed Time**: How long the algorithm has been running
- **Value Row**: The numeric values of each column

Press **`q`** to close the visualizer at any time.

## How It Works

Bogosort is the most hilariously inefficient sorting algorithm. It works by:

1. Randomly shuffling the array
2. Checking if the array is sorted
3. If not sorted, go back to step 1
4. Repeat until sorted (which could take... a very long time! 🎰)

Watch the bars animate as they shuffle around, and marvel at how long it can take to sort even a small array. With 25 elements, you might be waiting a while!

## Requirements

- Neovim 0.7+
- Lazy.nvim plugin manager

## License

See the LICENSE file for details.
