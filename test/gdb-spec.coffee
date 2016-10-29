GDB = require '../src'
sinon = require 'sinon'
assert = require 'assert'

describe 'GDB core', ->
    gdb = null
    beforeEach ->
        gdb = new GDB()
        #gdb.onGdbmiRaw (data) -> console.log data

    afterEach -> gdb?.destroy()

    describe 'Connecting and disconnecting', ->
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

    describe 'When connected', ->
        beforeEach ->
            gdb.connect()

        it 'accepts cli commands and emits console-output event', ->
            spy = sinon.spy()
            gdb.onConsoleOutput spy
            gdb.send_cli 'show version'
            .then ->
                assert spy.called

        it 'ignore comment lines on cli', ->
            gdb.send_cli ' #some comment'

        it 'rejects bad cli command with exception', ->
            gdb.send_cli 'badcommand'
            .then ->
                assert(not "Shouldn't get here")
            .catch (err) ->
                assert(err.constructor is Error)

        it 'accepts cwd', ->
            gdb.setCwd('.')

        it 'rejects invalid cwd', ->
            gdb.setCwd('./unlikely-to-exist')
            .then ->
                assert(not "Shouldn't get here")
            .catch (err) ->
                assert(err.constructor is Error)
