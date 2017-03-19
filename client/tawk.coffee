plugin_handle = null

###############################################################################
# Client Bus (exported through global variable)
###############################################################################

window.statebus_ready or= []
window.statebus_ready.push(->
  window.tawkbus = statebus()
  tawkbus.sockjs_client("/*", "https://tawk.space")
  window.tawk = tawkbus.sb
  tawk.janus_initialized = false

  unsavable = (obj) ->
    throw new Error("Cannot save #{obj.key}")

  tawkbus('connections').to_fetch = (key) ->
    connections = tawk['/connections']
    if not connections.all
      connections.all = []

    _: tawk['/connections'].all or []

  tawkbus('connections').to_save = unsavable

  tawkbus('connection/*').to_fetch = (key) ->
    target_id = key.split('/')[1]
    conn = tawk.connections.find (el) -> el.id == target_id

    _: conn or {id: target_id}

  tawkbus('connection/*').to_save = unsavable

  tawkbus('_groups').to_fetch = (key) ->
    groups = {}
    for conn in tawk.connections
      if conn.active and conn.space == get_space()
        if conn.group not of groups
          groups[conn.group] = []
        groups[conn.group].push(conn)

    for gid, members of groups
      members.sort (a, b) ->
        return a.timeEntered - b.timeEntered

    _: groups

  tawkbus('group/*').to_fetch = (key) ->
    gid = key.split('/')[1]

    _:
      members: (tawk._groups[gid] or [])

  tawkbus('gids').to_fetch = (key) ->
    groups = tawk._groups
    gids = (gid for gid, members of groups)
    gids.sort (gidA, gidB) ->
      # Uses the fact that members lists are already sorted
      return groups[gidA][0].timeEntered - groups[gidB][0].timeEntered

    _: gids

  tawkbus('active_connections').to_fetch = (key) ->
    count = 0
    for conn in tawk.connections
      if conn.active and conn.space == get_space()
        count += 1

    _: count

  tawkbus('dimensions').to_fetch = (key) ->
    connections = tawk['/connections']
    active_connections = tawk.active_connections

    screen_width = tawk.window.width
    screen_height = tawk.window.height

    # 240 x 180 is the minimum
    person_height = 180
    person_width = 240

    # Hacky way to render groups as big as possible
    # when there are only a few people in the space
    if active_connections <= 1
      person_height = Math.max(screen_height - 60, person_height)
      person_width = Math.max(screen_width / 2 - 60, person_width)
    else if active_connections <= 2
      person_height = Math.max(screen_height - 60, person_height)
      person_width = Math.max(screen_width / 3 - 60, person_width)
    else if active_connections <= 4
      person_height = Math.max(screen_height / 2 - 60, person_height)
      person_width = Math.max(screen_width / 3 - 60, person_width)
    else if active_connections <= 7
      person_height = Math.max(screen_height / 2 - 60, person_height)
      person_width = Math.max(screen_width / 4 - 60, person_width)

    if person_height > person_width * 3 / 4
      person_height = person_width * 3 / 4
    else if person_width > person_height * 4 / 3
      person_width = person_height * 4 / 3

    _:
      person_height: Math.round(person_height)
      person_width: Math.round(person_width)

  tawkbus('window').to_fetch = (key) ->
    _:
      width: window.innerWidth
      height: window.innerHeight - $("#topbar").outerHeight(true)

  window.onresize = () ->
    tawkbus.dirty 'window'
)
###############################################################################
# React render functions
###############################################################################

dom.TAWK = ->
  space = if @props.space? then @props.space else ''
  name = if @props.name? then @props.name else 'Anonymous ' + random_numbers(4)
  video = if @props.video? then @props.video else true
  audio = if @props.audio? then @props.audio else true

  # Have to make sure we get all connections to choose
  # whether to join the first group
  connections = tawk['/connections']
  if @loading()
    return DIV {}, 'Loading...'

  me = tawk['/connection']
  if not me.id
    me.id = random_string(16)
    me.name = name
    me.group = tawk.gids[0] or random_string(16)
    me.timeEntered = Date.now()
    me.active = true
    me.space = space
    me.video = video
    me.audio = audio

  if not tawk.janus_initialized
    initialize_janus(me.id, me.space)
    tawk.janus_initialized = true

  DIV
    id: 'tawk'
    style:
      height: 'auto'
      minHeight: '85%'
      clear: 'both'
    for gid in tawk.gids
      GROUP
        gid: gid
    if tawk.drag.dragging
      GROUP
        gid: tawk.drag.ghostGroup

dom.GROUP = ->
  gid = @props.gid
  members = tawk['group/' + gid].members or []

  group_info = tawk['/group/' + gid]
  group_editing = tawk['editing-' + gid]
  if not group_editing.timer
    group_editing.text = (if group_info.text == undefined then 'This is your group scratch space' else group_info.text)

  divSize = group_size(members.length or 1) # ghost group is size 1

  DIV
    id: gid
    className: (if tawk.drag.over == gid then 'dark-gray' else 'light-gray')
    style:
      float: 'left'
      margin: '20px'
      borderRadius: '15px'
      minWidth: divSize.width * tawk.dimensions.person_width + 'px'
      maxWidth: divSize.width * tawk.dimensions.person_width + 'px'
      # Height varies depending on size of textarea
      # Div around people sets height of that portion

    onMouseEnter: (e) ->
      tawk['/connection'].mouseover = gid

    onMouseLeave: (e) ->
      tawk['/connection'].mouseover = null

    DIV
      style:
        height: divSize.height * tawk.dimensions.person_height + 'px'
        position: 'relative'
      for user, index in members
        if user != null
          PERSON
            person: user
            borders: choose_borders(index, divSize)
            position: abs_position_in_group(index, divSize, tawk.dimensions)
    if members.length
      GROWING_TEXTAREA
        className: 'form-control'
        rows: 2
        style:
          clear: 'both'
          width: '100%'
          backgroundColor: 'inherit'
          borderBottomLeftRadius: '15px'
          borderBottomRightRadius: '15px'
          outline: 'none'
          border: '1px solid #aaa'
        value: group_editing.text
        onChange: (e) ->
          group_editing.text = e.target.value
          if group_editing.timer
            clearTimeout group_editing.timer
          group_editing.timer = setTimeout ->
            group_editing.timer = null
            group_info.text = group_editing.text
          , 500

dom.GROUP.refresh = ->
  gid = @props.gid

  $(@getDOMNode()).droppable
    tolerance: 'pointer'
    accept: '.person'
    greedy: true
    over: ->
      tawk.drag.over = gid
    out: ->
      if tawk.drag.over == gid
        # If not, another over event has fired on another group
        # and we do not want to clear the group
        tawk.drag.over = null

dom.PERSON = ->
  person = @props.person
  borders = @props.borders
  top = @props.position.top
  left = @props.position.left
  me = tawk['/connection']
  stream = tawk['stream/' + person.id]
  height = tawk.dimensions.person_height
  width = tawk.dimensions.person_width

  DIV
    position: 'absolute'
    left: left
    top: top
    DIV
      title: person.name
      id: person.id
      className: 'person'
      style:
        height: height + 'px'
        width: width + 'px'
        cursor: (if person.id == me.id then 'pointer' else '')
        opacity: (if should_hear_fully(person, me) then 1.0 else 0.5)
      if person.id == me.id
        AV_CONTROL_BAR()
      else
        AV_VIEW_BAR
          person: person
      if person.video
        transform = 'scaleX(-1)'
        if tawk['connection/' + person.id].flip_y
          transform += ' scaleY(-1)'
        DIV
          style:
            transform: transform
            width: '100%'
            height: height + 'px'
          onDoubleClick: =>
            me.flip_y = not me.flip_y
          VIDEO
            autoPlay: 'true'
            src: stream.url
            style:
              position: 'relative'
              height: '100%'
              width: '100%'
              zIndex: '-1'
              # These properties are flipped horizontally because the div is flipped horizontally
              borderTopLeftRadius: (if borders.topRight then '10px' else '')
              borderTopRightRadius: (if borders.topLeft then '10px' else '')
      else
        DIV
          style:
            backgroundColor: 'black'
            height: '100%'
            width: '100%'
            textAlign: 'center'
            fontSize: (height / 180) + 'em'
            textColor: 'white'
            borderTopLeftRadius: (if borders.topLeft then '10px' else '')
            borderTopRightRadius: (if borders.topRight then '10px' else '')
          DIV {},
            DIV
              person.name
            BR {},
            DIV
              if person.audio
                '(Audio-Only)'
              else
                '(Muted)'
      if person.audio
        DIV
          style:
            position: 'absolute'
            bottom: 0
            right: 0
            height: stream.volume + 'px'
            width: '20px'
            borderLeft: '5px solid #7FFF00'
          AUDIO
            autoPlay: 'true'
            src: stream.url

dom.PERSON.refresh = ->
  person = @props.person
  borders = @props.borders
  stream = tawk['stream/' + person.id]
  me = tawk['/connection']

  volume = 0
  if person.id != me.id
    if should_hear_fully(person, me)
      volume = 1.0
    else
      volume = 0.04
  vids = @getDOMNode().getElementsByTagName('video')
  if vids.length
    vids[0].volume = 0
  auds = @getDOMNode().getElementsByTagName('audio')
  if auds.length
    auds[0].volume = volume

  if me.id == person.id
    $(@getDOMNode().querySelector('.person')).draggable
      disabled: false
      refreshPositions: true
      zIndex: 1000
      start: (e, ui) ->
        tawk.drag.over = null # set while you mouseover groups
        tawk.drag.dragging = true
        tawk.drag.ghostGroup = random_string 16
      stop: (e, ui) ->
        if not tawk.drag.over or me.group != tawk.drag.over
          me.group = tawk.drag.over or tawk.drag.ghostGroup
          me.timeEntered = Date.now()

        tawk.drag.over = null
        tawk.drag.dragging = false
        tawk.drag.ghostGroup = null

        ui.helper.css
          top: 0
          left: 0
  else
    $(@getDOMNode().querySelector('.person')).draggable
      disabled: true

dom.AV_CONTROL_BAR = ->
  me = tawk['/connection']
  DIV
    style:
      position: 'absolute'
      width: '100%'
      bottom: '0'
      left: '0'
      zIndex: '100'
      textAlign: 'right'
    BUTTON
      className: 'btn btn-' + (if me.video then 'default' else 'danger')
      SPAN
        className: 'fa fa-video-camera' + (if me.video then '' else '-slash')
      onClick: (e) ->
        if me.video
          plugin_handle and plugin_handle.muteVideo()
          me.video = false
        else
          plugin_handle and plugin_handle.unmuteVideo()
          me.video = true
    BUTTON
      className: 'btn btn-' + (if me.audio then 'default' else 'danger')
      SPAN
        className: 'fa fa-microphone' + (if me.audio then '' else '-slash')
      onClick: (e) ->
        if me.audio
          plugin_handle and plugin_handle.muteAudio()
          me.audio = false
        else
          plugin_handle and plugin_handle.unmuteAudio()
          me.audio = true

dom.AV_VIEW_BAR = ->
  person = @props.person
  DIV
    style:
      position: 'absolute'
      width: '100%'
      bottom: '0'
      left: '0'
      zIndex: '100'
      textAlign: 'right'
    if not person.audio
      BUTTON
        className: 'btn btn-danger'
        disabled: 'disabled'
        SPAN
          className: 'fa fa-microphone-slash'

# Auto growing text area.
# Transfers props to a TEXTAREA.
dom.GROWING_TEXTAREA = ->
  @props.style ||= {}
  @props.style.minHeight ||= 40
  @props.style.height = \
      @local.height || @props.initial_height || @props.style.minHeight
  @props.style.fontFamily ||= 'inherit'
  @props.style.lineHeight ||= '22px'
  @props.style.resize ||= 'none'
  @props.style.outline ||= 'none'

  # save the supplied onChange function if the client supplies one
  _onChange = @props.onChange

  @props.onClick = (ev) ->
    ev.preventDefault(); ev.stopPropagation()

  @props.onChange = (ev) =>
    _onChange?(ev)
    @adjustHeight()

  @adjustHeight = =>
    textarea = @getDOMNode()

    if !textarea.value || textarea.value == ''
      h = @props.initial_height || @props.style.minHeight

      if h != @local.height
        @local.height = h
        save @local
    else
      min_height = @props.style.minHeight
      max_height = @props.style.maxHeight

      # Get the real scrollheight of the textarea
      h = textarea.style.height
      textarea.style.height = '' if @last_value?.length > textarea.value.length
      scroll_height = textarea.scrollHeight
      textarea.style.height = h  if @last_value?.length > textarea.value.length

      if scroll_height != textarea.clientHeight
        h = scroll_height + 5
        if max_height
          h = Math.min(scroll_height, max_height)
        h = Math.max(min_height, h)

        if h != @local.height
          @local.height = h
          save @local

    @last_value = textarea.value

  TEXTAREA @props

dom.GROWING_TEXTAREA.refresh = ->
  @adjustHeight()

random_string = (length) ->
  Math.round((Math.pow(36, length + 1) - Math.random() * Math.pow(36, length)))
    .toString(36)
    .slice(1)

random_numbers = (length) ->
  Math.round((Math.pow(10, length + 1) - Math.random() * Math.pow(10, length)))
    .toString(10)
    .slice(1)

should_hear_fully = (person, me) ->
  me.group in [person.group, person.mouseover] or
    (me.mouseover in [person.group, person.mouseover] and me.mouseover != null)

group_size = (num_people) ->
  floor = Math.floor(Math.sqrt(num_people))
  ceil = Math.ceil(Math.sqrt(num_people))

  if floor == ceil
    height: floor
    width: floor
  else if num_people > floor * ceil
    height: ceil
    width: ceil
  else
    height: floor
    width: ceil

choose_borders = (index, divSize) ->
  x = index % divSize.width
  y = Math.floor(index / divSize.width)

  topLeft: (x == 0 and y == 0)
  topRight: (x == divSize.width - 1 and y == 0)

abs_position_in_group = (index, divSize, dimensions) ->
  x = index % divSize.width
  y = Math.floor(index / divSize.width)

  top: y * dimensions.person_height
  left: x * dimensions.person_width

get_space = ->
  window.location.pathname.split('/')[1]

###############################################################################
# Send and receive video streams
###############################################################################

# This section is a little complicated because Janus requires multiple
# roundtrips for nearly everything. Suggestions on improvement are welcome.

recieved_stream = (stream, person_id) ->
  # Put stream (url) in state so the audio/video can be rendered
  tawk['stream/' + person_id] =
    url: URL.createObjectURL(stream)
    volume: 0

  # Save volume we receive for each stream to render as a green bar
  speech = hark(stream, {interval: 200, play: false})
  speech.on 'volume_change', (decibals, threshold) ->
    if decibals < threshold
      # Probably not human speech
      decibals = 0
    # Transform to 0-100% scale
    tawk['stream/' + person_id].volume = -2 * decibals

# Tell Janus to publish our video stream to the server
# Note that the hook when we get a local stream is actually
# a separate callback to janus.attach
publish_local_stream = (audio) ->
  plugin_handle.createOffer
    media:
      audioRecv: false
      videoRecv: false
      audioSend: audio
      videoSend: true
    success: (jsep) ->
      plugin_handle.send
        message:
          request: "configure"
          audio: audio
          video: true
        jsep: jsep
    error: (error) ->
      if audio
        console.error 'no_camera', 'No camera allowed', 'Trying audio-only mode'
        publish_local_stream false
      else
        console.error 'no_camera', 'No camera or microphone allowed', 'You are a listener'

new_remote_feed = (janus, feed) ->
  remote_feed = null
  {id, space} = JSON.parse feed.display
  janus.attach
    plugin: "janus.plugin.videoroom"
    onremotestream: (stream) -> recieved_stream(stream, id)
    error: console.error
    success: (ph) ->
      remote_feed = ph
      remote_feed.send
        message:
          request: "join"
          room: 1234
          ptype: "listener"
          feed: feed.id
    onmessage: (msg, jsep) ->
      if jsep
        remote_feed.createAnswer
          jsep: jsep
          error: console.error
          media:
            audioSend: false
            videoSend: false
          success: (jsep) ->
            remote_feed.send
              jsep: jsep
              message:
                request: "start"
                room: 1234

initialize_janus = (my_id, my_space) ->
  Janus.init
    callback: ->
      if not Janus.isWebrtcSupported()
        alert "No WebRTC support in your browser. You must use Chrome, Firefox, or Edge"

      janus = new Janus(
        server: 'https://tawk.space:8089/janus'
        error: console.error
        success: ->
          # Connect to the videoroom plugin
          janus.attach
            plugin: "janus.plugin.videoroom"
            error: console.error
            onlocalstream: (stream) -> recieved_stream(stream, my_id)
            success: (ph) ->
              # Join plugin as a publisher (able to both send and receive streams)
              plugin_handle = ph
              plugin_handle.send
                message:
                  request: "join"
                  room: 1234
                  ptype: "publisher"
                  display: JSON.stringify
                    id: my_id
                    space: my_space
            onmessage: (msg, jsep) ->
              # Janus is informing us of publishers we do not know about
              publishers = msg["publishers"] or []
              for feed in publishers
                {id, space} = JSON.parse feed.display
                if space == my_space
                  new_remote_feed janus, feed

              # The plugin_handle.send call to join as a publisher succeeded.
              # We can now send our video to everybody
              if msg["videoroom"] == "joined"
                publish_local_stream true

              if jsep
                plugin_handle.handleRemoteJsep
                  jsep: jsep
      )