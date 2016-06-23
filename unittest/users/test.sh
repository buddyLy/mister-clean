for x in $(find ~/tmp/users/user1 -size +13 -atime +0d -type f -print0 | xargs -0 ls); do echo "value $x"; done

