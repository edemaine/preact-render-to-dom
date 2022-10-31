# preact-render-to-dom

This package is a rewrite of
[preact-render-to-string](https://github.com/preactjs/preact-render-to-string)
to render Preact virtual DOM content directly to DOM,
without any support for reactivity or updates.

It's intended for rendering static documents, such as SVG images.
In particular, it's helpful on NodeJS when rendering to another virtual
implementation of real DOM, specifically one of:

* [xmldom](https://github.com/xmldom/xmldom)
* [jsdom](https://github.com/jsdom/jsdom)

Compared to rendering via preact-render-to-string, followed by parsing via
xmldom or jsdom, this package is ~7x or ~25x faster, respectively.
Try `npm test` yourself!

[SVG Tiler](https://github.com/edemaine/svgtiler) uses this package
to more quickly convert Preact VDOM to xmldom intermediate form
used to compose the entire document, before rendering everything to a file.

## Usage

See [test.coffee](test.coffee) for examples of usage.

### Real DOM

```js
import {RenderToDom} from 'preact-render-to-dom';
const dom = new RenderToDom().render(preactVDom);
```

### xmldom

```js
import {RenderToXMLDom} from 'preact-render-to-dom';
import xmldom from '@xmldom/xmldom';
const dom = new RenderToXMLDom({xmldom}).render(preactVDom);
```

### jsdom

```js
import {RenderToJSDom} from 'preact-render-to-dom';
import jsdom from 'jsdom';
const dom = new RenderToJSDom({jsdom}).render(preactVDom);
```

### Options

The `RenderTo*Dom` classes support a single options argument,
which can have the following properties:

* `svg: true`: start in SVG mode (not needed if top-level tag is `<svg>`)
* `skipNS: true`: don't bother using `document.createElementNS` in SVG mode
  (saves time, and usually not needed with `xmldom` for example)
* `RenderToDom` only:
  * `document`: an interface like the browser's `document`
    (defaults to `document` global if available)
  * `DOMParser`: an interface like the browser's `DOMParser`
    (needed only if nodes do not support the `innerHTML` interface)
* `RenderToXMLDom` only:
  * `xmldom`: the result of importing `@xmldom/xmldom`
* `RenderToJSDom` only:
  * `jsdom`: the result of importing `jsdom`, or the `JSDOM` class within

## License

The code is released under an [MIT license](LICENSE), the same license as
[preact-render-to-string](https://github.com/preactjs/preact-render-to-string)
on which this code is heavily based.
