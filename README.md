# node-gdb
[![npm](https://img.shields.io/npm/v/node-gdb.svg)](https://www.npmjs.com/package/node-gdb)
[![Build Status](https://travis-ci.org/gsmcmullin/node-gdb.svg?branch=master)](https://travis-ci.org/gsmcmullin/node-gdb)
[![Codecov](https://img.shields.io/codecov/c/github/gsmcmullin/node-gdb.svg)](https://codecov.io/gh/gsmcmullin/node-gdb)
[![deps](https://david-dm.org/gsmcmullin/node-gdb/status.svg)](https://david-dm.org/gsmcmullin/node-gdb)
[![devDeps](https://david-dm.org/gsmcmullin/node-gdb/dev-status.svg)](https://david-dm.org/gsmcmullin/node-gdb?type=dev)
[![Gitter](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/atom-gdb-debugger/Lobby)

GDB integration for Node.js

This module provides an interface for controlling GDB from Node.js applications.
It began as part of the `atom-gdb-debugger` project, but has been split off into
its own package with no atom dependencies.

This is still very experimental and under construction.  If you try it, please
stop by the Gitter channel and let us know what you think.

## Public API
[draft, subject to change]

`class GDB`
 - `constructor()` - create a new GDB instance
 - `onConsoleOutput(cb)` - invoke the callback on GDB console output
 - `onConnect(cb)` - invoke the callback when GDB is running
 - `onDisconnect(cb)` - invoke the callback when GDB exits
 - `connect(command)` - start a new GDB child process, returns a `Promise`
 - `disconnect()` - exit the currently connected GDB child, returns a `Promise`
 - `send_cli(cmd)` - send a CLI command to GDB, returns a `Promise`
 - `destroy()` - destory GDB class and free associated resources
 - `setFile(file)` - set target executable and symbol file, returns a `Promise`
 - `setCwd(path)` - set working directory for target, returns a `Promise`
 - `exec` - an `ExecState` instance
 - `breaks` - a `BreakpointManager` instance
 - `vars` - a `VariableManager` instance

`class ExecState`
 - `start()`
 - `continue()`
 - `next()`
 - `step()`
 - `finish()`
 - `interrupt()`
 - `getThreads()`
 - `getFrames([thread])`
 - `getLocals([frame, [thread]])`
 - `selectFrame(frame, [thread])`

`class BreakpointManager`
 - `observe(cb)` - invoke the callback with each existing and future `Breakpoint`
 - `insert(location)` - returns a `Promise` of the new `Breakpoint`

`class Breakpoint`
 - `onChanged(cb)`
 - `onDeleted(cb)`
 - `remove()`

`class VariableManager`
 - `observe(cb)`
 - `add(expr)`
 - `evalExpression(expr, [frame, [thread]])`

`class Variable`
 - `onChanged(cb)`
 - `onDeleted(cb)`
 - `addChildren()`
 - `assign(value)`
 - `remove()`
