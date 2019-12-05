
import groovy.sql.Sql

sql = Sql.newInstance(
    'jdbc:h2:~/test',
    'sa',
    '',
    'org.h2.Driver')

>>d

sql.eachRow('select * from USER') {
    println "${it.id}, ${it.firstName}"
}