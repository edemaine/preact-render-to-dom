import {RenderToXMLDom} from './index.js'
import {h} from 'preact'
import {renderToString} from 'preact-render-to-string'
import xmldom from '@xmldom/xmldom'

reps = 1000000

renderToXMLDom = new RenderToXMLDom xmldom

vdom = h 'svg', {viewBox: "0 0 200 200", xmlns: 'http://www.w3.org/2000/svg'}, [
  h 'g', {id: 'g1'}, [
    h 'rect', {id: 'rect1', x: 0, y: 0, width: 100, height: 100, fill: 'red'}
  ],
  h 'use', {href: "#g1", x: 100, y: 100}
]

before = performance.now()
for [0...reps]
  dom = null
after = performance.now()
nothingConvert = after - before
console.log "Null conversion: #{nothingConvert / reps * 1000}us"

before = performance.now()
for [0...reps]
  dom = renderToXMLDom.render vdom
after = performance.now()
directConvert = after - before
directXML = new xmldom.XMLSerializer().serializeToString dom

console.log "Direct conversion: #{(directConvert - nothingConvert) / reps * 1000}us"

parser = new xmldom.DOMParser()
before = performance.now()
for [0...reps]
  xml = renderToString vdom
  dom = parser.parseFromString xml, 'image/svg+xml'
after = performance.now()
doubleConvert = after - before
doubleXML = new xmldom.XMLSerializer().serializeToString dom

console.log "Double conversion: #{(doubleConvert - nothingConvert) / reps * 1000}us"
console.log "Speedup:", doubleConvert / directConvert

console.log()
console.log directXML
unless directXML == doubleXML
  console.log '*** DIFFERENT OUTPUT FROM DOUBLE CONVERSION:'
  console.log doubleXML
