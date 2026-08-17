# Text Editor Demo

A simple terminal-based text editor built with Zig. This project demonstrates fundamental text editor functionality including file operations, text manipulation, search capabilities, and a user-friendly interface.

## Features

### File Operations
- **Open files**: Load existing text files for editing
- **Save files**: Write changes back to disk (Ctrl+S)
- **Quit safely**: Three-press confirmation to prevent accidental exits (Ctrl+Q)
- **Dirty state tracking**: Visual indicator when file has unsaved changes

### Text Editing
- **Full cursor navigation**: Arrow keys, Page Up/Down, Home, End
- **Text insertion**: Type characters to insert at cursor position
- **Deletion**: Backspace to remove characters
- **Tab support**: Tab key inserts 8 spaces
- **Newline handling**: Enter key creates new lines

### Search Functionality
- **Find mode**: Press Ctrl+F to enter search mode
- **Forward/Backward navigation**: Navigate through search results
- **Case-sensitive matching**: Exact string matching
- **Visual highlighting**: Found text is highlighted in the editor
- **Status feedback**: Clear messages about search results

### User Interface
- **Status bar**: Displays filename, dirty state, and cursor position
- **Message bar**: Shows temporary status messages (5-second timeout)
- **Clean layout**: Vim-style `~` indicators for empty lines
- **Responsive design**: Adapts to terminal window size

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Ctrl+S` | Save file |
| `Ctrl+Q` | Quit (press 3 times to confirm) |
| `Ctrl+F` | Enter find/search mode |
| `↑` / `k` | Move cursor up |
| `↓` / `j` | Move cursor down |
| `←` / `h` | Move cursor left |
| `→` / `l` | Move cursor right |
| `Page Up` | Scroll up one page |
| `Page Down` | Scroll down one page |
| `Home` | Go to beginning of line |
| `End` | Go to end of line |
| `Enter` | Insert new line |
| `Backspace` | Delete character before cursor |
| `Tab` | Insert 8 spaces |
| `Escape` | Exit find mode |

### Find Mode Controls

When in find mode (after pressing Ctrl+F):

| Key | Action |
|-----|--------|
| `Enter` | Search forward for next occurrence |
| `Shift+Enter` | Search backward for previous occurrence |
| `Escape` | Exit find mode |
| `Backspace` | Delete last character from search query |
| Other chars | Add to search query |

## Installation

### Prerequisites

- [Zig](https://ziglang.org/download/) (version 0.11.0 or later)
- A POSIX-compatible terminal

### Building from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/StarPlatinumDS/text-editor-demo.git
   cd text-editor-demo
   ```

2. Build the project:
   ```bash
   zig build
   ```

3. Run the editor:
   ```bash
   ./zig-out/bin/text-editor-demo [filename]
   ```

   Or with Zig directly:
   ```bash
   zig run src/main.zig -- [filename]
   ```

## Usage

### Opening a File

Start the editor with an optional filename:

```bash
# Open a specific file
./zig-out/bin/text-editor-demo myfile.txt

# Start with empty buffer
./zig-out/bin/text-editor-demo
```

### Basic Editing

1. **Navigate**: Use arrow keys or vim-style keys (h/j/k/l) to move the cursor
2. **Insert text**: Simply start typing to insert characters at the cursor position
3. **Delete text**: Use Backspace to remove characters
4. **Save**: Press `Ctrl+S` to save your changes
5. **Quit**: Press `Ctrl+Q` three times to exit

### Searching Text

1. Press `Ctrl+F` to enter find mode
2. Type your search query
3. Press `Enter` to find the next occurrence
4. Press `Shift+Enter` to find the previous occurrence
5. Press `Escape` to exit find mode

Found text will be highlighted in the editor, and the status bar will show your current position in the search results.

## Project Structure

```
text-editor-demo/
├── src/
│   ├── main.zig          # Entry point and main editor loop
│   ├── editor.zig        # Core editor logic and state management
│   ├── buffer.zig        # Text buffer implementation
│   ├── display.zig       # Terminal rendering and UI
│   └── input.zig         # Keyboard input handling
├── build.zig             # Zig build configuration
└── README.md             # This file
```

### Module Descriptions

- **main.zig**: Initializes the editor, handles command-line arguments, and runs the main event loop
- **editor.zig**: Contains the core `Editor` struct with state management for cursor position, scroll offset, and mode handling
- **buffer.zig**: Implements the `Buffer` struct for efficient text storage and manipulation using gap buffer or rope data structures
- **display.zig**: Handles terminal output using ANSI escape codes for cursor movement, colors, and screen clearing
- **input.zig**: Processes keyboard input, including special keys and control sequences

## Technical Details

### Terminal Handling

The editor uses raw terminal mode to capture all keyboard input directly, bypassing normal line buffering. This allows for:
- Real-time response to key presses
- Capture of control characters and special keys
- Full screen control using ANSI escape sequences

### Text Storage

The text buffer uses a dynamic array of lines, where each line is a separate allocated string. This approach provides:
- Efficient line insertion and deletion
- Simple cursor positioning
- Easy file I/O operations

### Search Implementation

Search functionality maintains:
- Current search query string
- List of all match positions in the buffer
- Index of current match for navigation
- Automatic re-search when query changes

## Limitations

This is a demonstration project with some intentional limitations:

- **No undo/redo**: Changes cannot be undone once made
- **Basic encoding**: Assumes UTF-8 or ASCII text (no explicit encoding detection)
- **No syntax highlighting**: All text is displayed in the same style
- **Single file only**: Cannot open multiple files simultaneously
- **No mouse support**: Navigation is keyboard-only
- **Limited line length**: Very long lines may cause display issues

### Development Setup

```bash
# Clone the repository
git clone https://github.com/StarPlatinumDS/text-editor-demo.git
cd text-editor-demo

# Build in debug mode
zig build

# Run tests (if available)
zig build test

# Build in release mode
zig build -Doptimize=ReleaseFast
```

## Acknowledgments

This project was inspired by:
- [kilo](https://github.com/antirez/kilo) - A small text editor in C
- [vis](https://github.com/martanne/vis) - A vi-like editor
- The Zig community and standard library

---

**Note**: This is a learning project and demonstration of Zig programming. It's not intended for production use.