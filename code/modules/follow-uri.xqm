xquery version "1.0";
(:~
 : follow-uri function and mode
 :
 : Open Siddur Project
 : Copyright 2009-2011 Efraim Feinstein 
 : Licensed under the GNU Lesser General Public License, version 3 or later
 : 
 :)
module namespace uri="http://jewishliturgy.org/transform/uri";

import module namespace debug="http://jewishliturgy.org/transform/debug"
	at "/code/modules/debug.xqm"; 
import module namespace grammar="http://jewishliturgy.org/transform/grammar"
	at "/code/grammar-parser/grammar2.xqm";
import module namespace jcache="http://jewishliturgy.org/modules/cache"
	at "/code/modules/cache-controller.xqm";
import module namespace nav="http://jewishliturgy.org/modules/nav"
  at "/code/api/modules/nav.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace jx="http://jewishliturgy.org/ns/jlp-processor";
declare namespace p="http://jewishliturgy.org/ns/parser";
declare namespace r="http://jewishliturgy.org/ns/parser-result";

declare variable $uri:xpointer-grammar :=
	document {
		<p:grammar>{
			doc('/code/grammar-parser/xpointer.xml')/p:grammar | 
			doc('/code/grammar-parser/xptr-tei.xml')/p:grammar
		}</p:grammar>
	};
declare variable $uri:fragmentation-cache-type := 'fragmentation';

(:~ return an element by id, relative to a node :)
declare function uri:id(
	$id as xs:string,
	$root as node()
	) as element()? {
	($root/id($id), $root//*[@jx:id = $id])[1]
};

(:~ Given a relative URI and a context,  
 :  resolve the relative URI into an absolute URI
 : @param $uri contains the URI to make absolute
 : @param $context The URI is absolute relative to this context.
 :)
declare function uri:absolutize-uri(
	$uri as xs:string,
  $context as node()?
  ) as xs:anyURI {
	let $base-path as xs:anyURI := uri:uri-base-path($uri)
	return
    xs:anyURI(
    if ($base-path and (matches($uri, "^http[s]?://") or doc-available($base-path)))
    then $uri
    else resolve-uri($uri,base-uri($context) )
    )
};
  
(:~ Returns the base path part of an absolute URI 
 : @param $uri An absolute URI
 :)
declare function uri:uri-base-path(
	$uri as xs:string
	) as xs:anyURI {
  xs:anyURI(
  	if (contains($uri,'#')) 
    then substring-before($uri,'#') 
    else $uri
  )
};
  
(:~ Base resource of a URI (not including the fragment or query string)
 : @param $uri A URI
 :)
declare function uri:uri-base-resource(
	$uri as xs:string
	) as xs:anyURI {
  let $base-path as xs:string := string(uri:uri-base-path($uri))
  return
    xs:anyURI(
      if (contains($base-path, '?'))
      then substring-before($base-path, '?')
      else $base-path
    )
};
  
(:~ Returns the fragment portion of an absolute URI.  
 : The return value excludes the #
 : @param $uri An absolute URI
 :)
declare function uri:uri-fragment(
	$uri as xs:string
	) as xs:anyURI {
  xs:anyURI(
  	if (contains($uri, '#')) 
    then substring-after($uri, '#') 
    else ''
  )
};
  
(:----------- follow parsed XPointer --------:)
(:~ Get nodes, given $document and $fragment :)
declare function uri:node-from-pointer(
	$document as document-node()?,
  $fragment as xs:anyURI
  ) as node()* {
  debug:debug($debug:detail + 1,
  	'func:node-from-pointer: document',
  	$document), 
  debug:debug($debug:detail + 1, 
    'func:node-from-pointer: fragment',
    ($fragment)  
  ),
  if ($document)
  then
  	uri:follow-parsed-xpointer(
  		grammar:clean(
  			grammar:parse(string($fragment), 'Pointer', $uri:xpointer-grammar)
	  	),
  		$document
  	)
  else ()
};

(:~ follow a parsed xpointer within a given document :)
declare function uri:follow-parsed-xpointer(
	$node as node()*,
	$doc as document-node()
	) as node()* {
	for $n in $node
	return
		typeswitch($n)
		case element(r:Shorthand) return uri:r-Shorthand($n, $doc)
		case element(r:PointerPart) return uri:r-PointerPart($n, $doc)
		default  
			(: pass-through. Including r:Pointer, r:SchemeBased :)
			return uri:follow-parsed-xpointer($n/node(), $doc)	
};

(: Follow a pointer one step 
 r:Pointer -- pass-through
 r:SchemeBased -- pass-through
:)
  
(:~ Follow a shorthand pointer (aka, id) :)
declare function uri:r-Shorthand(
	$context as element(),
	$doc as document-node()
	) as node()* {
	uri:id(string($context), $doc)
};

(:~ Follow a scheme-based pointer.
 : Send out a debug warning if the scheme is unsupported.
 :
 :)
declare function uri:r-PointerPart(
	$context as element(),
	$doc as document-node()
	) as node()* {
	if ($context/r:SchemeName='range')
	then
		let $pointers as element(r:Pointer)+ :=
      grammar:clean(grammar:parse(string($context/r:SchemeData), 'RangeData', $uri:xpointer-grammar))/r:Pointer
    let $left-pointer as node() :=
      uri:follow-parsed-xpointer($pointers[1], $doc)
    let $right-pointer as node() :=
    	uri:follow-parsed-xpointer($pointers[2], $doc)
    return (
    	debug:debug($debug:detail, 'r:PointerPart:pointers', $pointers),
      (: pointers[1] contains the beginning, 
       : pointers[2] contains the end.  It is an error for:
    	 : (1) pointers[2] to be before pointers[1] in document order
       : (2) pointers[1] or pointers[2] to be empty
     	 :)    
      if (empty($left-pointer) or empty($right-pointer))
      then
        debug:debug(
        	$debug:error,
        	'r:PointerPart',
          'In a pointer range expression, both pointers must resolve to a location'
          )
      else if ($left-pointer >> $right-pointer)
      then
        debug:debug(
        	$debug:error,
        	'r:PointerPart',
          ('In a pointer range expression, the second pointer must follow ',
          'the first in document order. ',
          '[1] = ', $left-pointer, ' [2] = ', $right-pointer)
          )
      else
      	(:util:get-fragment-between($left-pointer, $right-pointer, false()),$right-pointer:)
        $left-pointer|
          ($left-pointer/following-sibling::node() intersect 
            $right-pointer/preceding-sibling::node())|
          $right-pointer 
    )
	else 
		debug:debug($debug:warn,
			'r:PointerPart',
      ('Unsupported scheme: ', r:SchemeName, ' in ', $context)
    )
};
  
(: ----------- following TEI pointers -----:)
(:~ Follow a given pointer $uri, 
 : including any subsequent pointers or links (such as tei:join). 
 : The $steps parameter indicates the number of pointer steps to follow if 
 : another pointer is pointed to by $uri.  
 : If $steps is negative, the chain is followed infinitely (or
 : until another pointer limits it).
 :)
declare function uri:follow-uri(
	$uri as xs:string,
  $context as node(),
  $steps as xs:integer
	) as node()* {
  uri:follow-cached-uri($uri, $context, $steps, ())
};

(:~ Given the full path to a document, return its cached version path
 :)
declare function uri:cached-document-path(
	$path as xs:string
	) as xs:string {
	jcache:cached-document-path($path)
};

declare function uri:follow-cached-uri(
  $uri as xs:string,
  $context as node(),
  $steps as xs:integer,
  $cache-type as xs:string?
  ) as node()* {
  uri:follow-cached-uri($uri, $context, $steps, $cache-type, ())
};

(:~ Extended uri:follow-uri() to allow caching.
 : @param $cache-type Which cache to use
 :)
declare function uri:follow-cached-uri(
	$uri as xs:string,
  $context as node(),
  $steps as xs:integer,
  $cache-type as xs:string?,
  $intermediate-ptrs as xs:boolean?
	) as node()* {
  let $full-uri as xs:anyURI :=
  	uri:absolutize-uri($uri, $context)
	let $base-path := uri:uri-base-path($full-uri)
  let $fragment as xs:anyURI := 
  	uri:uri-fragment(string($full-uri))      
	let $document as document-node()? := 
	  let $doc := nav:api-path-to-sequence($base-path)
	  return
	    if ($cache-type=$uri:fragmentation-cache-type)
	    then doc(uri:cached-document-path(document-uri($doc)))
	    else $doc
	let $pointer-destination as node()* :=
		uri:follow(
			if ($fragment) 
      then uri:node-from-pointer($document, $fragment) 
      else $document,
      $steps,
      $cache-type,
      false(),
      $intermediate-ptrs)
	return (
    debug:debug($debug:detail + 1, 
    	'func:follow-uri',
    	('uri =', $uri,
        ' full-uri =', $full-uri, 
        ' base-path =', $base-path,
        ' fragment =', $fragment,
        ' cache-type = ', $cache-type)),
    debug:debug($debug:detail, ($fragment, $steps, $pointer-destination), 
      string-join(('func:follow-pointer(): $fragment, $steps, $pointer-destination for ', 
        $base-path,'#',$fragment), '')),
    $pointer-destination
  )
};

declare function uri:fast-follow(
  $uri as xs:string,
  $context as node(),
  $steps as xs:integer
  ) as node()* {
  uri:fast-follow($uri, $context, $steps, ())
};

(:~ faster routine to follow a pointer one step
 : Only works with shorthand pointers and #range() and 
 : does not support caching
 :)
declare function uri:fast-follow(
  $uri as xs:string,
  $context as node(),
  $steps as xs:integer,
  $intermediate-ptrs as xs:boolean?
  ) as node()* {
  let $full-uri as xs:anyURI :=
    uri:absolutize-uri($uri, $context)
  let $base-path as xs:anyURI := 
    uri:uri-base-path($full-uri)
  let $fragment as xs:anyURI := 
    uri:uri-fragment(string($full-uri))
  let $document as document-node()? := 
    nav:api-path-to-sequence($base-path)
  let $pointer-destination as node()* :=
    if ($fragment) 
    then 
      uri:follow(
        if (starts-with($fragment, "range("))
        then 
          let $left := 
            $document//id(substring-before(substring-after($fragment, "("), ","))
          let $right := 
            $document//id(substring-before(substring-after($fragment, ","), ")"))
          return ($left | ($left/following::* intersect $right/preceding::*) | $right)
        else $document//id($fragment), 
        $steps, (), true(), 
        $intermediate-ptrs
      )
    else $document
  return $pointer-destination
};

declare function uri:follow-tei-link(
	$context as element()
	) as node()* {
	uri:follow-tei-link($context, -1, (), ())
};

declare function uri:follow-tei-link(
	$context as element(),
	$steps as xs:integer
	) as node()* {
	uri:follow-tei-link($context, $steps, (), ())
};

declare function uri:follow-tei-link(
  $context as element(),
  $steps as xs:integer,
  $cache-type as xs:string?
  ) as node()* {
  uri:follow-tei-link($context, $steps, $cache-type, ())
};

declare function uri:follow-tei-link(
  $context as element(),
  $steps as xs:integer,
  $cache-type as xs:string?,
  $fast as xs:boolean?
  ) as node()* {
  uri:follow-tei-link($context, $steps, $cache-type, $fast, ())
};

(:~ Handle the common processing involved in following TEI links
 : @param $context Link to follow
 : @param $steps Specifies the maximum number of steps to evaluate.  Negative for infinity (default)
 : @param $cache-type Specifies the cache type to use (eg, fragmentation).  Empty for none (default)
 : @param $fast use the fast follow algorithm (default false())
 : @param $intermediate-ptrs return all intermediate pointers, not just the final result (default false())
 :)
declare function uri:follow-tei-link(
	$context as element(),
  $steps as xs:integer,
  $cache-type as xs:string?,
  $fast as xs:boolean?,
  $intermediate-ptrs as xs:boolean?
	) as node()* {
  let $targets as xs:string+ := 
    tokenize(string($context/(@target|@targets)),'\s+')
  return
    for $t in $targets
    return
    	if ($steps = 0)
    	then $context
    	else 
    	  if ($fast)
    	  then
    	    uri:fast-follow($t, $context, 
    	      uri:follow-steps($context, $steps),
    	      $intermediate-ptrs)
    	  else
          uri:follow-cached-uri(
          	$t, $context, 
            uri:follow-steps($context, $steps), 
            $cache-type,
            $intermediate-ptrs)
};

(:~ calculate the number of steps to pass to follow-cached-uri()
 : given a pointer or link element 
 :)
declare function uri:follow-steps(
  $context as element()
  ) as xs:integer {
  uri:follow-steps($context, -1)
};

(:~ calculate the number of steps to pass to follow-cached-uri()
 : given a pointer or link element and a number already followed 
 :)
declare function uri:follow-steps(
  $context as element(),
  $steps as xs:integer
  ) as xs:integer {
  let $evaluate as xs:string? := 
    ($context/(@evaluate,../(tei:linkGrp|../tei:joinGrp)/@evaluate)[1])/string()
  return
    if ($evaluate='none') 
    then 0 
    else if ($evaluate='one') 
    then 1
    else $steps - 1
};

(:----------- follow a pointer mode -------------:)

declare function uri:follow(
  $node as node()*,
  $steps as xs:integer,
  $cache-type as xs:string?
  ) as node()* {
  uri:follow($node, $steps, $cache-type, (), ())
};


(:~ 
 : @param $fast use uri:fast-follow()
 : @param $intermediate-ptrs return all intermediates in addition
 :    to the end result of following the pointer
 :)
declare function uri:follow(
	$node as node()*,
	$steps as xs:integer,
	$cache-type as xs:string?,
	$fast as xs:boolean?,
	$intermediate-ptrs as xs:boolean?
	) as node()* {
	for $n in $node
	return
		typeswitch($n)
		case element(tei:join) return uri:tei-join($n, $steps, $cache-type, $fast, $intermediate-ptrs)
		case element(tei:ptr) return uri:tei-ptr($n, $steps, $cache-type, $fast, $intermediate-ptrs) 
		default return $n
};  

(:~ follow tei:ptr, except tei:ptr[@type=url] :)
declare function uri:tei-ptr(
	$context as element(),
  $steps as xs:integer,
  $cache-type as xs:string?,
  $fast as xs:boolean?,
  $intermediate-ptrs as xs:boolean?
  ) as node()* {
 	if ($context/@type = 'url')
 	then $context
 	else (
 	  $context[$intermediate-ptrs],
 	  if ($context/parent::tei:joinGrp)
 	  then uri:tei-join($context, $steps, $cache-type, $fast, $intermediate-ptrs)
 	  else uri:follow-tei-link($context, $steps, $cache-type, $fast, $intermediate-ptrs)
 	) 
};

(:~ tei:join or tei:ptr acting as a join being followed.  
 : If @result is present, produce an element with the namespace URI
 : the same as that of the context node
 :)
declare function uri:tei-join(
	$context as element(),
	$steps as xs:integer,
	$cache-type as xs:string?,
	$fast as xs:boolean?,
	$intermediate-ptrs as xs:boolean?
	) as node()* {
	$context[$intermediate-ptrs],
	let $joined-elements as element()* :=
		for $pj in uri:follow-tei-link($context, $steps, $cache-type, $fast, $intermediate-ptrs)
    return
    	if ($pj/@scope='branches')
      then $pj/node()
      else $pj
  let $result as xs:string? := 
  	string($context/(@result, parent::tei:joinGrp/@result)[1]) 
  return
  	if ($result)
  	then 
  		element { QName($context/namespace-uri(), $result)} {
      	$joined-elements
      }
    else
     	$joined-elements
};
