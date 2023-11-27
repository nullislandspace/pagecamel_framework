ALTER TABLE users ADD COLUMN appkey text NOT NULL DEFAULT '';

CREATE OR REPLACE FUNCTION usersappkeytrigger() RETURNS trigger AS $$
    use strict;

    if(!defined($_TD->{new}->{appkey}) || $_TD->{new}->{appkey} eq '') {
        my $appkey = '';
        for(1..40) {
            my $num = int(rand(26)+65);
            my $char = chr($num);
            if(rand(10) > 5) {
                $char = lc $char;
            }
            $appkey .= $char;
        }

        $_TD->{new}->{appkey} = $appkey;

        return "MODIFY"; # Modified
    }

    return; # return unmodified

$$ LANGUAGE plperlu;

CREATE TRIGGER users_appkey_trigger
    BEFORE INSERT OR UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION usersappkeytrigger();


UPDATE users SET username = username;

