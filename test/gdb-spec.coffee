GDB = require '../src'
sinon = require 'sinon'
assert = require 'assert'

describe 'GDB core', ->
    gdb = null
    beforeEach ->
        gdb = new GDB()
        #gdb.onGdbmiRaw (data) -> console.log data

    afterEach -> gdb?.destroy()

    it 'emits connected when connecting', ->
        spy = sinon.spy()
        gdb.onConnect spy
        gdb.connect().then ->
            assert spy.called

    it 'emits disconnected when disconnecting', (done) ->
        gdb.onDisconnect done
        gdb.connect()
        .then ->
            gdb.disconnect()
        return

    it 'accepts cli commands and emits console-output event', ->
        spy = sinon.spy()
        gdb.onConsoleOutput spy
        gdb.connect()
        .then ->
            gdb.send_cli 'show version'
        .then ->
            assert spy.called

    it 'ignore comment lines on cli', ->
        gdb.connect()
        .then ->
            gdb.send_cli ' #some comment'

    it 'rejects bad cli command with exception', ->
        gdb.connect()
        .then ->
            gdb.send_cli 'badcommand'
        .then ->
            throw new Error "Shouldn't get here"
        .catch (err) ->
            assert(err.constructor is Error)
