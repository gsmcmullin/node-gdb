GDB = require '../lib'

describe 'GDB', ->
    gdb = null
    beforeEach ->
        gdb = new GDB()
        #gdb.onGdbmiRaw (data) -> console.log data

    afterEach -> gdb?.destroy()

    it 'emits connected when connecting', (done) ->
        spy = jasmine.createSpy('connected')
        gdb.onConnect spy
        gdb.connect().then ->
            expect(spy).toHaveBeenCalled()
            done()

    it 'emits disconnected when disconnecting', (done) ->
        gdb.onDisconnect done
        gdb.connect()
        .then ->
            gdb.disconnect()

    it 'accepts cli commands and emits console-output event', (done) ->
        spy = jasmine.createSpy('output')
        gdb.onConsoleOutput spy
        gdb.connect()
        .then ->
            gdb.send_cli 'show version'
        .then ->
            expect(spy).toHaveBeenCalled()
            done()

    it 'rejects bad cli command with exception', (done) ->
        gdb.connect()
        .then ->
            gdb.send_cli ' #some comment'
        .then ->
            done()

    it 'rejects bad cli command with exception', (done) ->
        gdb.connect()
        .then ->
            gdb.send_cli 'badcommand'
        .then ->
            throw new Error "Shouldn't get here"
        .catch (err) ->
            expect(err.constructor).toEqual(Error)
            done()
