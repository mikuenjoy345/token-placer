#!/usr/bin/env perl
use Mojolicious::Lite -signatures;
use Mojo::Util qw(md5_sum);
use Mojo::Cache;
use JSON qw(from_json);
use Smart::Comments;
{
	package TieAlphabet;
	use strict;

	sub TIEARRAY {
		my ($pkg) = @_;
		bless [qw(A B C D E F G H I J K L M N O P Q R S T U V W X Y Z)], $pkg;
	}

	sub FETCH {
		my ($obj, $index) = @_;
		return 'too big' if $index > (26*26+26); # only doing a-zz, not infinity.
		$index < 26
			? return $obj->[$index]
			: return $obj->[ (int $index/26) - 1 ] . $obj->[ $index % 26 ]
	}

	sub FETCHSIZE {
		return 26*26+26;
	}
	1;
}

my $cache  = Mojo::Cache->new(max_keys => 10);
my $update = Mojo::Cache->new(max_keys => 10);
my @alphabet_array;
tie @alphabet_array, 'TieAlphabet';

get '/' => sub ($c) {
  $c->render(template => 'index');
};

any '/field' => sub ($c) {
	$c->render(template => 'field');
};

get '/create_table' => sub ($c) {
	return $c->render(template => 'create_table_form') unless $c->param('cols');
	my $values = $c->req->params->to_hash;
	$c->stash(cols => $values->{cols});
	$c->stash(rows => $values->{rows});

	$c->stash(md5 => $values->{md5_sum});

	$c->stash(alphabet_array => \@alphabet_array);
	$c->render(template => 'create_table');
};

post '/create_table' => sub ($c) {
	my $cols = $c->param('columns');
	my $rows = $c->param('rows');
	my $md5 = $c->param('md5sum');
	if (!($cols and $rows)) {
		return $c->render(text => "No, this is broken, I think. Cols: $cols, Rows: $rows");
	}
	if (! (($cols =~ m/^\d+$/) and ($rows =~ m/^\d+$/)) ) {
		return $c->render(text => "No, this is broken, I think. Cols: $cols, Rows: $rows");
	}
	
	$c->stash(cols => $cols);
	$c->stash(rows => $rows);
	$c->stash(md5 => $md5);
	$c->stash(alphabet_array => \@alphabet_array);
	$c->render(template => 'create_table');
};

# this gets called when someone clicks "Share Room"
post '/short' => sub ($c) {
	my $json = from_json($c->req->body);
	my $long_boi = $json->{url};
	my $old_boi;
	if (exists $json->{old} and $json->{old} ne 'undefined') {
	  $old_boi = %{ from_json($c->req->body)}{old}; 
	}
	my $short = md5_sum $long_boi;
	$c->render(json => {'data' => {'short' => "https://$ENV{TOKEN_HOSTNAME}:$ENV{TOKEN_PORT}/sh/" . $short, 'md5' => $short }} );
	$cache->set( $short => $long_boi);
	$update->set($old_boi => $short) if $old_boi;
	# now to create persistant short -> long_boi ...
	open(my $fh, '>>', './short.txt') or die;
	# TODO gzip this
	say $fh "$short => $long_boi";
	close $fh;
	if ($old_boi) {
		# TODO add a 'next' and 'back' buttons for this
		open(my $fh, '>>', './update.txt') or die;
		say $fh "$old_boi => $short";
		# multiple people can 'Share Room' on the same md5sum which will be tricky to handle
		# I'll figure it out later.
		close $fh;
	}
};

get '/sh/:short' => sub ($c) {
	if ($cache->get($c->param('short') )) {
		return $c->redirect_to($cache->get( $c->param("short") ) . '&md5_sum=' . $c->param('short') );
	}
	else {
		# TODO un-gzip this
		open(my $fh, '<', './short.txt') or return $c->render(text => "Sorry.");
		while (my $line = <$fh>) {
			my @line = split / => /, $line;
			if ($line[0] eq $c->param('short')) {
				chomp $line[1];
				chomp $line[0];
				$c->redirect_to($line[1] . '&md5_sum=' . $line[0]);
				last;
			}
		}
		close $fh;
		return $c->render(text => "Sorry.");
	}
};

# this gets called auto-matically, by js.
get '/update/:update' => sub ($c) {
	my $i = $c->param('update');
	$c->param('update') 
		? return $c->render(json => {'data' => $update->get($i) })  # eventually leads to /sh/:short
		: return $c->render(json => {'data' => undef});
};

app->start;
__DATA__

@@ index.html.ep
% layout 'default';
% title 'Welcome';
<h1>Welcome to the Mojolicious real-time web framework!</h1>

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= title %></title></head>
  <body><%= content %></body>
</html>
