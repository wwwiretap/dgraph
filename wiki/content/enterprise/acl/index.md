+++
date = "Fri Jan 18 16:07:43 PST 2019"
title = "Access Control List"
+++

Access Control List (ACL) provides protection to your data stored in
Dgraph. When the ACL feature is turned on, A client , e.g. dgo or dgraph4j, Must login first using a
pair of username and password before executing any transactions, and is only allowed to access the
data that has been given granted to the user. This document has three parts First we will talk about
the admin operations needed for setting up ACL.  then we will talk about how to use a client to
access data when the ACL feature is turned on.  Finally for the curious minds we will describe how
ACL is implemented within Dgraph.

## Turn on ACL in your cluster
The ACL Feature can be turned on by following these steps 

1. Make sure your use case is covered under a
contract with Dgraph, given ACL is one of our Enterprise features. You probably don't want legal
surprises down the road. Here is how to connect with us to establish a contract. 
2. create a plan text
file, and store a randomly generated secret key in it. The secret key is used by Alpha servers to
sign Json Web Tokens (JWT), And as you’ve probably guessed, it’s critical to keep the secret key as
a secret.  Since we are using the HMAC-SHA256 as the signing algorithm, we require the secrets to
have at least 256 bits, i.e.  32 ascii characters.  
3. start all the alpha servers in your cluster with
the options --enterprise-feature and --hmac-secret-file, and make sure they are all using the same
secret key file. Here is an example. If you are using docker here's an example of a docker-compose
file.

## Access data using a client when ACL is turned on
Now your cluster is running with the ACL feature turned on. Next let's set up the ACL rules. A typical workflow is the following
 reset the root password

1. create a regular user
2. create a group
3. assign the user to the group
4. assign predicate permissions to the group
5. assign more predicate permissions to the group 
6. check information about the user, the group and the permissions

2nd section

Now that I see our rules are set let's go ahead and use the client to access the data.
first let's store some data in Dgraph
dgo client and dgraph4j client example

Next let’s query the data,  and the run some mutations

And lastly let's try to alter the data schema.

## How ACL is implemented inside Dgraph
This section cover some implementation details regarding how the ACL feature is implemented inside Dgraph. This section is not necessary reading for how to use  the ACL feature.
Storing the ACL data

Authenticating login requests, returning accessJWT

Automatic login through the refreshJwt

The ACL cache

Authorizing user requests

Related security considerations
TLS connections between client and cluster. For now plaintext connections within the cluster.


Request for feedback.
How to support Regex predicates?
