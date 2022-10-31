import {h, options, Fragment} from 'preact'

SVGNS = 'http://www.w3.org/2000/svg'

## https://github.com/preactjs/preact-render-to-string/blob/master/src/constants.js
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
## https://github.com/preactjs/preact-render-to-string/blob/master/src/util.js
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
getContext = (nodeName, context) ->
  if (cxType = nodeName.contextType)?
    context[cxType[COMPONENT]]?.props.value ? cxType[PARENT]
  else
    context
UNSAFE_NAME = /[\s\n\\/='"\0<>]/

## Convert an Object style to a CSSText string, from
## https://github.com/preactjs/preact-render-to-string/blob/master/src/util.js
JS_TO_CSS = {}
CSS_REGEX = /([A-Z])/g
IS_NON_DIMENSIONAL = /acit|ex(?:s|g|n|p|$)|rph|grid|ows|mnc|ntw|ine[ch]|zoo|^ord|^--/i
styleObjToCss = (s) ->
  str = ''
  for prop, val of s
    if val? and val != ''
      str += ' ' if str
      str +=
        if prop[0] == '-'
          prop
        else
          JS_TO_CSS[prop] ?= prop.replace(CSS_REGEX, '-$1').toLowerCase()

      if typeof val == 'number' and IS_NON_DIMENSIONAL.test(prop) == false
        str = "#{str}: #{val}px;"
      else
        str = "#{str}: #{val};"
  str or undefined

renderFunctionComponent = (vnode, context) ->
  c = createComponent vnode, context
  cctx = getContext vnode.type, context
  vnode[COMPONENT] = c

  # If a hook invokes setState() to invalidate the component during rendering,
  # re-render it up to 25 times to allow "settling" of memoized states.
  # Note:
  #   This will need to be updated for Preact 11 to use internal.flags rather than component._dirty:
  #   https://github.com/preactjs/preact/blob/d4ca6fdb19bc715e49fd144e69f7296b2f4daa40/src/diff/component.js#L35-L44
  renderHook = options[RENDER]
  count = 0
  while c[DIRTY] and count++ < 25
    c[DIRTY] = false
    renderHook? vnode
    # stateless functional components
    rendered = vnode.type.call c, vnode.props, cctx
  rendered

renderClassComponent = (vnode, context) ->
  nodeName = vnode.type
  cctx = getContext nodeName, context

  c = new nodeName vnode.props, cctx
  vnode[COMPONENT] = c
  c[VNODE] = vnode
  c[DIRTY] = true  # turn off stateful re-rendering
  c.props = vnode.props
  c.state ?= {}
  c[NEXT_STATE] ?= c.state
  c.context = cctx

  if nodeName.getDerivedStateFromProps?
    c.state = {...c.state,
      ...nodeName.getDerivedStateFromProps c.props, c.state}
  else if c.componentWillMount
    c.componentWillMount()

    # If the user called setState in cWM we need to flush pending,
    # state updates. This is the same behavior in React.
    unless c[NEXT_STATE] == c.state
      c.state = c[NEXT_STATE]

  options[RENDER]? vnode

  c.render c.props, c.state, c.context

XLINK = /^xlink:?./
normalizePropName = (name, isSvgMode) ->
  switch name
    when 'className' then 'class'
    when 'htmlFor' then 'for'
    when 'defaultValue' then 'value'
    when 'defaultChecked' then 'checked'
    when 'defaultSelected' then 'selected'
    else
      if isSvgMode and XLINK.test name
        name.toLowerCase().replace /^xlink:?/, 'xlink:'
      else
        name

normalizePropValue = (name, v) ->
  if name == 'style' and v? and typeof v == 'object'
    styleObjToCss v
  else if name[0] == 'a' and name[1] == 'r' and typeof v == 'boolean'
    # always use string values instead of booleans for aria attributes
    # also see https://github.com/preactjs/preact/pull/2347/files
    String v
  else
    v

export class RenderToDom
  constructor: (@options = {}) ->
    @document = @options.document ? document
    if @options.DOMParser?
      @DOMParser = new @options.DOMParser

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

    parent = h Fragment, null
    parent[CHILDREN] = [vnode]

    dom = @recurse vnode, context, @options.svg ? false, undefined, parent
    options[COMMIT]? vnode, []
    options[SKIP_EFFECTS] = previousSkipEffects
    dom

  recurse: (vnode, context, isSvgMode, selectValue, parent) ->
    # null, undefined, true, false, '' render as nothing
    return if not vnode? or vnode in [true, false, '']

    # Text VNodes get escaped as HTML
    unless typeof vnode == 'object'
      return if typeof vnode == 'function'
      return @document.createTextNode vnode

    # Recurse into children / Arrays and build into a fragment
    if Array.isArray vnode
      fragment = @document.createDocumentFragment()
      for child in vnode
        fragment.appendChild \
          @recurse child, context, isSvgMode, selectValue, parent
      return fragment

    # VNodes have {constructor:undefined} to prevent JSON injection
    return if vnode.constructor != undefined

    vnode[PARENT] = parent
    options[DIFF]? vnode

    {type, props} = vnode

    # Invoke rendering on Components
    if typeof type == 'function'
      if type == Fragment
        rendered = props.children
      else
        if type.prototype and typeof type.prototype.render == 'function'
          rendered = renderClassComponent vnode, context
        else
          rendered = renderFunctionComponent vnode, context

        component = vnode[COMPONENT]
        if component.getChildContext
          context = {...context, ...component.getChildContext()}

      # When a component returns a Fragment node we flatten it in core, so we
      # need to mirror that logic here too
      if rendered? and rendered.type == Fragment and not rendered.key?
        rendered = rendered.props.children

      # Recurse into children before invoking the after-diff hook
      dom = @recurse rendered, context, isSvgMode, selectValue, parent

      options[DIFFED]? vnode
      vnode[PARENT] = undefined

      options.unmount? vnode

      return dom

    # Render Element VNodes to DOM
    if not @options.skipNS and @document.createElementNS? and
       isSvgMode or type == 'svg'
      dom = @document.createElementNS SVGNS, type
    else
      dom = @document.createElement type
    if props?
      {children} = props
      for name, val of props
        continue if name in ['key', 'ref', '__self', '__source', 'children']
        continue if name == 'className' and 'class' of props
        continue if name == 'htmlFor' and 'for' of props
        continue if UNSAFE_NAME.test name

        name = normalizePropName name, isSvgMode
        val = normalizePropValue name, val
        if name == 'dangerouslySetInnerHTML'
          html = val?.__html
        else if type == 'textarea' and name == 'value'
          # <textarea value="a&b"> --> <textarea>a&amp;b</textarea>
          children = val
        else if (val or val == 0 or val == '') and typeof val != 'function'
          if val == true or val == ''
            val = name
            dom.setAttribute name, ''
            continue

          if name == 'value'
            if type == 'select'
              selectValue = val
              continue
            else if (
              # If we're looking at an <option> and it's the currently selected one
              type == 'option' and
              selectValue == val and
              # and the <option> doesn't already have a selected attribute on it
              not ('selected' in props)
            )
              dom.setAttribute 'selected', ''
          dom.setAttribute name, val

    if UNSAFE_NAME.test type
      throw new Error "#{type} is not a valid HTML tag name in #{s}"

    childSvgMode =
      type == 'svg' or (type != 'foreignObject' and isSvgMode)
    if html
      @setInnerHTML dom, html, childSvgMode
    else if typeof children == 'string'
      dom.appendChild @document.createTextNode children
    else if Array.isArray children
      vnode[CHILDREN] = children
      for child in children
        if child? and child != false
          ret = @recurse child, context, childSvgMode, selectValue, parent
          # Skip if we received an empty string
          dom.appendChild ret if ret
    else if children? and children not in [false, true]
      vnode[CHILDREN] = [children]
      ret = @recurse children, context, childSvgMode, selectValue, parent
      # Skip if we received an empty string
      dom.appendChild ret if ret

    options[DIFFED]? vnode
    vnode[PARENT] = undefined
    options.unmount? vnode

    dom

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
