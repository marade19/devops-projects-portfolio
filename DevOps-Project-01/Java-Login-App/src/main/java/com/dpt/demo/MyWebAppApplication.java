package com.dpt.demo;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.boot.web.servlet.support.SpringBootServletInitializer;
@SpringBootApplication
public class MyWebAppApplication extends SpringBootServletInitializer {
        @Override
        protected SpringApplicationBuilder configure(SpringApplicationBuilder application) {
                return application.sources(MyWebAppApplication.class);
        }
        public static void main(String[] args) {
                SpringApplication.run(MyWebAppApplication.class, args);
        }
}
