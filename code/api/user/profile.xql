xquery version "1.0";
(: user profile editing API
 : valid properties are:
 :  name, email, orgname
 : 
 : Parameters: 
 :  property=propertyname
 :  format=
 :    text returns a normalized text representation
 :    xml returns the complete xml representation
 :
 : Method: GET
 : Return: 
 : Status: 
 :	200	OK
 : 	401 not authenticated
 :	403 authenticated as the wrong user
 :	404 nonexistent property
 :	
 :
 : Method: PUT
 : Parameters:
 :  property
 : Return: property result
 : Status codes: 204 OK, 401, 403, 404
 :
 : on error: returns an error element with a description
 :
 : Open Siddur Project
 : Copyright 2011 Efraim Feinstein <efraim@opensiddur.org>
 : Licensed under the GNU Lesser General Public License, version 3 or later
 :
 :)
import module namespace request="http://exist-db.org/xquery/request";
import module namespace util="http://exist-db.org/xquery/util";
import module namespace xmldb="http://exist-db.org/xquery/xmldb";

import module namespace app="http://jewishliturgy.org/modules/app"
  at "/code/modules/app.xqm";
import module namespace api="http://jewishliturgy.org/modules/api"
  at "/code/api/modules/api.xqm";  
import module namespace name="http://jewishliturgy.org/modules/name"
  at "/code/modules/name.xqm";
import module namespace paths="http://jewishliturgy.org/modules/paths"
	at "/code/modules/paths.xqm";
import module namespace user="http://jewishliturgy.org/modules/user"
  at "/code/modules/user.xqm";  

declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace err="http://jewishliturgy.org/errors";

(:~ return a reference to a property in the user profile.
 : if the profile doesn't exist, cause an error (and attempt to create a profile
 : so the request can be retried successfully)
 :)
declare function local:get-reference(
	$user-name as xs:string,
	$property as xs:string
	) as node()? {
	if ($paths:debug)
	then
		util:log-system-out(('get-reference(): user-profile-uri=', 
			app:concat-path(xmldb:get-user-home($user-name), 'profile.xml'),
			' I am:', xmldb:get-current-user()))
	else (),
	let $user-profile-uri := app:concat-path(xmldb:get-user-home($user-name), 'profile.xml')
	let $user-profile := 
		if (doc-available($user-profile-uri))
    then doc($user-profile-uri)/*
    else 
      if (user:new-profile($user-name))
      then (
        response:redirect-to(request:get-uri()),
        api:error((), "User profile did not exist and I successfully created it. Retry the request.")
      )
      else
        api:error(500, "User profile did not exist and could not be created")
	return
    if (root($user-profile) instance of document-node())
    then
      if ($property = 'name')
      then $user-profile/tei:name
      else if ($property = 'email')
      then $user-profile/tei:email
      else if ($property = 'orgname')
      then $user-profile/tei:orgName
      else
        api:error(404, 'Unknown property', $property)
    else (: $user-profile contains the error message :)
      $user-profile
};

(:
 : set a property in the profile
 :)
declare function local:put-property(
	$user-name as xs:string,
  $property as xs:string,
  $format as xs:string
  ) as element()? {
  let $reference := local:get-reference($user-name, $property)
  return
    if ($reference instance of element(error))
    then $reference
    else
      let $value := 
        typeswitch (api:get-data())
        case $data as xs:string return text { $data }
        default $data return $data
      let $new-value := 
        if ($property = 'name' and empty($value/element()))
        then
          (: name has to be converted :)
          element tei:name {
            $value/@*,
            name:string-to-name(string($value))
          }
        else
          (: take the value as-is :)
          $value
      return (
        if ($paths:debug)
        then
          util:log-system-out(('set ', $property, ' original:', $reference, ' replace:', $new-value))
        else (),
        if ($format = 'txt' and not($property = 'name'))
        then 
          update value $reference with $new-value
        else 
          update replace $reference with $new-value,
				response:set-status-code(204)
      )
};

(:~ return the current value of a property or format a given new value
 : in the format requested by format parameter
 :)
declare function local:get-property(
	$user-name as xs:string,
	$property as xs:string,
	$format as xs:string, 
	$value as item()?
	) as item()? {
	let $reference := ($value, local:get-reference($user-name, $property))[1]
	return 
		(: return the property :)
    if ($reference instance of element(error))
    then $reference
	  else if ($format = 'txt')
	  then (
      api:serialize-as('txt'),
			if ($property = 'name')
      then
      	name:name-to-string($reference) 
      else
       	string($reference) 
    )
	  else (
      api:serialize-as('xml'),
	  	$reference
    )
};

declare function local:get-property(
	$user-name as xs:string,
	$property as xs:string,
	$format as xs:string 
	) as item()? {
	local:get-property($user-name, $property, $format, ())
};

declare function local:delete-property(
  $user-name as xs:string,
  $property as xs:string
  ) as item()? {
  let $reference := local:get-reference($user-name, $property)
  return
    if ($reference instance of element(error))
    then $reference
    else (
      update delete $reference/node(),
      response:set-status-code(204)
    )
};

(: check if the property exists, if not, set error code 404 
 : the caller has to provide an error message
 :)
declare function local:has-property(
	$property as xs:string,
	$format as xs:string
	) as xs:boolean {
	let $valid-properties := ('name', 'orgname', 'email')
	let $valid-formats := ('', 'txt', 'xml')
	return 
		if ($property = $valid-properties and $format = $valid-formats)
		then true()
		else ( 
			response:set-status-code(404),
			false()
		)
};

if (api:allowed-method(('GET', 'PUT', 'DELETE')))
then
	let $user-name := request:get-parameter('user-name', ())
	let $property-req := request:get-parameter('property', ())
	let $property := 
		if (contains($property-req, '.'))
		then substring-before($property-req, '.')
		else $property-req
	let $format := 
		let $s := substring-after($property-req, '.')
		return
			if ($s) 
			then $s
			else 'xml'
	let $method := api:get-method()
	return
		if (api:require-authentication-as($user-name, true()))
		then 
			if (local:has-property($property, $format))
			then 
				if ($method = 'GET')
				then local:get-property($user-name, $property, $format)
				else if ($method = 'PUT') 
        then local:put-property($user-name, $property, $format)
        else local:delete-property($user-name, $property)
			else 
				api:error(404, concat('The property ', $property, ' is not found.'))
		else 
			(: not authenticated correctly. let require-authentication-as() set the error code :)
			api:error((), concat('You must be authenticated as ', $user-name, ' to access ', request:get-uri())) 
else 
	(: disallowed method :)
	()
