import {h, options, Fragment} from 'preact'

SVGNS = 'http://www.w3.org/2000/svg'

## https://github.com/preactjs/preact-render-to-string/blob/main/src/constants.js
DIFF = '__b'
RENDER = '__r'
DIFFED = 'diffed'
COMMIT = '__c'
SKIP_EFFECTS = '__s'
COMPONENT = '__c'
CHILDREN = '__k'
HOOKS = '__h'
VNODE = '__v'
DIRTY = '__d'
PARENT = '__'

## Dummy component helpers and other constants from
## https://github.com/preactjs/preact-render-to-string/blob/main/src/util.js
markAsDirty = -> @[DIRTY] = true
createComponent = (vnode, context) ->
  [VNODE]: vnode
  context: context
  props: vnode.props
  # silently drop state updates
  setState: markAsDirty
  forceUpdate: markAsDirty
  [DIRTY]: true
  [HOOKS]: []
UNSAFE_NAME = /[\s\n\\/='"\0<>]/
NAMESPACE_REPLACE_REGEX = /^(xlink|xmlns|xml)([A-Z])/
HTML_LOWER_CASE = /^accessK|^auto[A-Z]|^ch|^col|cont|cross|dateT|encT|form[A-Z]|frame|hrefL|inputM|maxL|minL|noV|playsI|readO|rowS|spellC|src[A-Z]|tabI|item[A-Z]/
SVG_CAMEL_CASE = /^ac|^ali|arabic|basel|cap|clipPath$|clipRule$|color|dominant|enable|fill|flood|font|glyph[^R]|horiz|image|letter|lighting|marker[^WUH]|overline|panose|pointe|paint|rendering|shape|stop|strikethrough|stroke|text[^L]|transform|underline|unicode|units|^v[^i]|^w|^xH/

## Convert an Object style to a CSSText string, from
## https://github.com/preactjs/preact-render-to-string/blob/main/src/util.js
JS_TO_CSS = {}
CSS_REGEX = /([A-Z])/g
IS_NON_DIMENSIONAL = /acit|ex(?:s|g|n|p|$)|rph|grid|ows|mnc|ntw|ine[ch]|zoo|^ord|^--/i
styleObjToCss = (s) ->
  str = ''
  for prop, val of s
    if val? and val != ''
      name =
        if prop[0] == '-'
          prop
        else
          JS_TO_CSS[prop] ?= prop.replace(CSS_REGEX, '-$&').toLowerCase()
      suffix = '?'
      if typeof val == 'number' and not name.startsWith('--') and
         not IS_NON_DIMENSIONAL.has(prop)
        suffix = 'px;'
      str = "#{str}#{name}:#{val}#{suffix}"
  str or undefined

export class RenderToDom
  constructor: (@options = {}) ->
    @document = @options.document ? document
    if @options.DOMParser?
      @DOMParser = new @options.DOMParser
    # Global state for the current render pass
    @beforeDiff = @afterDiff = @renderHook = @unmountHook = null

  setInnerHTML: (node, html, isSvgMode) ->
    if node.innerHTML?
      node.innerHTML = html
    else if @DOMParser?
      # Wrap in document element (for multiple tags) and parse
      if isSvgMode
        parsed = @DOMParser.parseFromString \
          "<svg xmlns=\"#{SVGNS}\">#{html}</svg>", 'image/svg+xml'
      else
        parsed = @DOMParser.parseFromString \
          "<html>#{html}</html>", 'text/html'
      for child in (child for child in parsed.documentElement.childNodes)
        node.appendChild child
    else
      throw new Error "RenderToDom: No innerHTML or DOMParser interface; pass DOMParser class via options"

  render: (vnode, context = {}) ->
    # Don't execute any effects by passing an empty array to `options[COMMIT]`.
    # Further avoid dirty checks and allocations by setting
    # `options[SKIP_EFFECTS]` too.
    previousSkipEffects = options[SKIP_EFFECTS]
    options[SKIP_EFFECTS] = true

    # store options hooks once before each synchronous render call
    @beforeDiff = options[DIFF]
    @afterDiff = options[DIFFED]
    @renderHook = options[RENDER]
    @unmountHook = options.unmount

    parent = h Fragment, null
    parent[CHILDREN] = [vnode]

    try
      return @recurse vnode, context, @options.svg ? false, undefined, parent
    finally
      # options._commit, we don't schedule any effects in this library right now,
      # so we can pass an empty queue to this hook.
      options[COMMIT]? vnode, []
      options[SKIP_EFFECTS] = previousSkipEffects

  # Recursively render VNodes to HTML.
  recurse: (vnode, context, isSvgMode, selectValue, parent) ->
    # null, undefined, true, false, '' render as empty fragment
    if not vnode? or vnode in [true, false, '']
      return @document.createDocumentFragment()

    # Text VNodes get escaped as HTML
    unless typeof vnode == 'object'
      return if typeof vnode == 'function'
      return @document.createTextNode vnode + ''

    # Recurse into children / Arrays and build into a fragment
    if Array.isArray vnode
      fragment = @document.createDocumentFragment()
      for child in vnode
        continue if not child? or typeof child == 'boolean'
        fragment.appendChild \
          @recurse child, context, isSvgMode, selectValue, parent
      return fragment

    # VNodes have {constructor:undefined} to prevent JSON injection
    return if vnode.constructor != undefined

    vnode[PARENT] = parent
    @beforeDiff? vnode

    {type, props} = vnode
    cctx = context

    # Invoke rendering on Components
    if typeof type == 'function'
      if type == Fragment
        # Fragments are the least used components of core that's why
        # branching here for comments has the least effect on perf.
        if props.UNSTABLE_comment
          return @document.createComment props.UNSTABLE_comment or ''
        rendered = props.children
      else
        {contextType} = type
        if contextType?
          provider = context[contextType.__c]
          cctx = if provider then provider.props.value else contextType.__

        if type.prototype and typeof type.prototype.render == 'function'
          rendered = @renderClassComponent vnode, context
          component = vnode[COMPONENT]
        else
          component =
            __v: vnode
            props: props
            context: cctx
            # silently drop state updates
            setState: markAsDirty
            forceUpdate: markAsDirty
            __d: true
            # hooks
            __h: []

          # If a hook invokes setState() to invalidate the component during rendering,
          # re-render it up to 25 times to allow "settling" of memoized states.
          # Note:
          #   This will need to be updated for Preact 11 to use internal.flags rather than component._dirty:
          #   https://github.com/preactjs/preact/blob/d4ca6fdb19bc715e49fd144e69f7296b2f4daa40/src/diff/component.js#L35-L44
          count = 0
          while component[DIRTY] and count++ < 25
            component[DIRTY] = false
            @renderHook? vnode
            rendered = type.call component, props, cctx
          component[DIRTY] = true

        if component.getChildContext?
          context = {...context, ...component.getChildContext()}

        if (type.getDerivedStateFromError or component.componentDidCatch) and
           options.errorBoundaries
          # When a component returns a Fragment node we flatten it in core, so we
          # need to mirror that logic here too
          if rendered? and rendered.type == Fragment and not rendered.key?
            rendered = rendered.props.children

          try
            return @recurse rendered, context, isSvgMode, selectValue, vnode
          catch err
            if type.getDerivedStateFromError
              component[NEXT_STATE] = type.getDerivedStateFromError err

            component.componentDidCatch? err, {}

            if component[DIRTY]
              rendered = @renderClassComponent vnode, context
              component = vnode[COMPONENT]

              if component.getChildContext?
                context = {...context, ...component.getChildContext()}

              if rendered? and rendered.type == Fragment and not rendered.key?
                rendered = rendered.props.children

              return @recurse rendered, context, isSvgMode, selectValue, vnode

            return @document.createDocumentFragment()
          finally
            @afterDiff? vnode
            vnode[PARENT] = undefined
            @unmountHook? vnode

      # When a component returns a Fragment node we flatten it in core, so we
      # need to mirror that logic here too
      if rendered? and rendered.type == Fragment and not rendered.key?
        rendered = rendered.props.children

      # Recurse into children before invoking the after-diff hook
      dom = @recurse rendered, context, isSvgMode, selectValue, parent

      @afterDiff? vnode
      vnode[PARENT] = undefined
      @unmountHook? vnode

      return dom

    # Render Element VNodes to DOM
    if not @options.skipNS and @document.createElementNS? and
       isSvgMode or type == 'svg'
      dom = @document.createElementNS SVGNS, type
    else
      dom = @document.createElement type

    children = null
    for name, val of props
      switch name
        when 'children'
          children = val
          continue

        # VDOM-specific props
        when 'key', 'ref', '__self', '__source'
          continue

        # prefer for/class over htmlFor/className
        when 'htmlFor'
          continue if 'for' in props
          name = 'for'
        when 'className'
          continue if 'class' in props
          name = 'class'

        # Form element reflected properties
        when 'defaultChecked'
          name = 'checked'
        when 'defaultSelected'
          name = 'selected'

        # Special value attribute handling
        when 'defaultValue', 'value'
          name = 'value'
          switch type
            # <textarea value="a&b"> --> <textarea>a&amp;b</textarea>
            when 'textarea'
              children = val
              continue
            # <select value> is serialized as a selected attribute on the matching option child
            when 'select'
              selectValue = val
              continue
            # Add a selected attribute to <option> if its value matches the parent <select> value
            when 'option'
              if selectValue == val and 'selected' not of props
                dom.setAttribute 'selected', ''
              continue

        when 'dangerouslySetInnerHTML'
          html = val?.__html
          continue

        # serialize object styles to a CSS string
        when 'style'
          val = styleObjToCss val if typeof v == 'object'
        when 'acceptCharset'
          name = 'accept-charset'
        when 'httpEquiv'
          name = 'http-equiv'

        else
          if NAMESPACE_REPLACE_REGEX.test name
            name = name.replace(NAMESPACE_REPLACE_REGEX, '$1:$2').toLowerCase()
          else if UNSAFE_NAME.test name
            continue
          else if (name[4] == '-' or name == 'draggable') and val?
            # serialize boolean aria-xyz or draggable attribute values as strings
            # `draggable` is an enumerated attribute and not Boolean. A value of `true` or `false` is mandatory
            # https://developer.mozilla.org/en-US/docs/Web/HTML/Global_attributes/draggable
            val += ''
          else if isSvgMode
            if SVG_CAMEL_CASE.test name
              if name == 'panose1'
                name = 'panose-1'
              else
                name = name.replace(/[A-Z]/g, '-$1').toLowerCase()
          else if HTML_LOWER_CASE.test name
            name = name.toLowerCase()

      # write this attribute to the buffer
      if val? and val != false and typeof val != 'function'
        if val == true or val == ''
          dom.setAttribute name, ''
        else
          dom.setAttribute name, val + ''

    if UNSAFE_NAME.test type
      throw new Error "#{type} is not a valid HTML tag name in #{s}"

    if html
      # dangerouslySetInnerHTML defined this node's contents
      @setInnerHTML dom, html, childSvgMode
    else if typeof children == 'string'
      # single text child
      dom.appendChild @document.createTextNode children
    else if children? and children not in [false, true]
      # recurse into this element VNode's children
      childSvgMode =
        type == 'svg' or (type != 'foreignObject' and isSvgMode)
      ret = @recurse children, context, childSvgMode, selectValue, parent
      dom.appendChild ret

    @afterDiff? vnode
    vnode[PARENT] = undefined
    @unmountHook? vnode

    dom

  renderClassComponent: (vnode, context) ->
    type = vnode.type
    isMounting = true
    if vnode[COMPONENT]
      isMounting = false
      c = vnode[COMPONENT]
      c.state = c[NEXT_STATE]
    else
      c = new type vnode.props, context

    vnode[COMPONENT] = c
    c[VNODE] = vnode
    c.props = vnode.props
    c.context = context
    c[DIRTY] = true  # turn off stateful re-rendering
    c.state ?= {}
    c[NEXT_STATE] ?= c.state

    if type.getDerivedStateFromProps?
      c.state = {...c.state,
        ...type.getDerivedStateFromProps c.props, c.state}
    else if isMounting and c.componentWillMount
      c.componentWillMount()

      # If the user called setState in cWM we need to flush pending,
      # state updates. This is the same behavior in React.
      unless c[NEXT_STATE] == c.state
        c.state = c[NEXT_STATE]
    else if not isMounting and c.componentWillUpdate
      c.componentWillUpdate()

    @renderHook? vnode

    c.render c.props, c.state, c.context

export class RenderToXMLDom extends RenderToDom
  constructor: (options) ->
    xmldom = options.xmldom
    super {...options,
      document: new xmldom.DOMImplementation().createDocument()
      DOMParser: xmldom.DOMParser
    }

export class RenderToJSDom extends RenderToDom
  constructor: (options) ->
    jsdom = options.jsdom
    jsdom = jsdom.JSDOM if jsdom.JSDOM?
    super {...options,
      document: new jsdom('<!DOCTYPE html>').window.document}
