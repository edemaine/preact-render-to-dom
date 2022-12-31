import {RenderToXMLDom, RenderToJSDom} from './index.js'
import {h, Fragment} from 'preact'
import {renderToString} from 'preact-render-to-string'
import xmldom from '@xmldom/xmldom'
import jsdom from 'jsdom'

xmldomDOMParser = new xmldom.DOMParser()
for {name, renderer, parser, stringify, reps} in [
  name: 'xmldom'
  renderer: new RenderToXMLDom {xmldom, skipNS: true}
  parser: (text) -> xmldomDOMParser.parseFromString text, 'image/svg+xml'
  stringify: (dom) -> new xmldom.XMLSerializer().serializeToString dom
  reps: 100000
  #reps: 1000000
,
  name: 'jsdom'
  renderer: new RenderToJSDom {jsdom}
  parser: (text) -> new jsdom.JSDOM("<!DOCTYPE html>" + text).window.document.body.children[0]
  stringify: (dom) -> dom.outerHTML
  reps: 1000
]
  console.log()
  console.log '***', name
  vdom = h 'svg', {viewBox: "0 0 200 200", xmlns: 'http://www.w3.org/2000/svg'}, [
    h 'g', {id: 'g1'}, [
      h 'rect', {id: 'rect1', x: 0, y: 0, width: 100, height: 100, fill: 'red'}
      h 'text', {y: 100, style: 'font-size: 50px'}, 'Hi'
      h Fragment
    ],
    h 'use', {href: "#g1", x: 100, y: 100}
    ## For testing innerHTML:
    #h 'desc', {dangerouslySetInnerHTML: {__html:
    #  'Made with <a href="https://github.com/edemaine/preact-render-to-dom">preact-render-to-dom</a>'}}
  ]

  before = performance.now()
  for [0...reps]
    dom = null
  after = performance.now()
  nothingConvert = after - before
  console.log "Null conversion: #{nothingConvert / reps * 1000}us"

  before = performance.now()
  for [0...reps]
    dom = renderer.render vdom
  after = performance.now()
  directConvert = after - before
  directXML = stringify dom

  console.log "Direct conversion: #{(directConvert - nothingConvert) / reps * 1000}us"

  before = performance.now()
  for [0...reps]
    xml = renderToString vdom
    dom = parser xml
  after = performance.now()
  doubleConvert = after - before
  doubleXML = stringify dom

  console.log "Double conversion: #{(doubleConvert - nothingConvert) / reps * 1000}us"
  console.log "Speedup:", doubleConvert / directConvert

  xml = renderToString vdom
  before = performance.now()
  for [0...reps]
    dom = parser xml
  after = performance.now()
  justParse = after - before
  console.log "Just parsing: #{(justParse - nothingConvert) / reps * 1000}us"
  console.log "Speedup:", justParse / directConvert

  console.log()
  console.log directXML
  unless directXML == doubleXML
    console.log '>>> DIFFERENT OUTPUT FROM DOUBLE CONVERSION:'
    #console.log dom
    console.log doubleXML
